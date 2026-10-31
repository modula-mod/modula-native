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
    @State private var comparePlan: PremiumPlan = .recommended
    @State private var expandedFAQ: String?

    var body: some View {
        SettingsScrollCanvas {
            PremiumHeroCard(plan: store.plan, previewing: store.isPreviewing)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Choose a plan").font(.headline)
                    Spacer()
                    Picker("Billing", selection: $store.selectedBilling) {
                        ForEach(PremiumBilling.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                    .accessibilityIdentifier("premium.billing")
                }
                ModulaGlassGroup(spacing: 10) {
                    VStack(spacing: 10) {
                        ForEach(PremiumPlan.paid) { plan in
                            PremiumPlanCard(
                                plan: plan,
                                billing: store.selectedBilling,
                                selected: store.selectedPlan == plan,
                                current: store.plan == plan
                            ) {
                                withAnimation(ModulaMotion.animation(.selection, personality: app.appearance.motion, reduceMotion: reduceMotion)) {
                                    store.selectedPlan = plan
                                    comparePlan = plan
                                }
                            }
                        }
                    }
                }
                PremiumPrimaryButton(plan: store.selectedPlan, currentPlan: store.plan, comingSoon: true) {}
                Text(PremiumPricing.placeholderNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("premium.placeholderNote")
            }

            comparison

            TelegramSettingsCard {
                TelegramRow(title: "Premium badge", symbol: "seal.fill", tint: app.appearance.accent.color, value: store.plan.showsBadge ? store.plan.shortTitle : "Core") {
                    app.navigation.open(.settings(.premium(.badge)))
                }
                .accessibilityIdentifier("premium.badge.link")
            }

            faq

            #if DEBUG
            PremiumDeveloperCard(store: store)
            #endif
        }
        .navigationTitle("Modula Premium")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("premium.hub")
    }

    private var comparison: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Compare with Core").font(.headline)
            Picker("Plan", selection: $comparePlan) {
                ForEach(PremiumPlan.paid) { Text($0.shortTitle).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("premium.comparePicker")
            TelegramSettingsCard {
                ForEach(Array(PremiumCatalog.comparison.enumerated()), id: \.element.id) { index, row in
                    PremiumComparisonRowView(row: row, plan: comparePlan)
                    if index < PremiumCatalog.comparison.count - 1 { TelegramDivider() }
                }
            }
            Text("Everything in Core stays free. Premium only adds.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("premium.compare")
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(PremiumPlan.horizon.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Modula Premium").font(.title3.weight(.semibold))
                    Text(statusLine).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Text(PremiumCatalog.positioning)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false, tint: PremiumPlan.horizon.tint.opacity(0.35), specular: true)
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

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: plan.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(plan.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(plan.title).font(.body.weight(.semibold))
                        if plan == .recommended {
                            PremiumPill(text: "Recommended", tint: plan.tint)
                        }
                        if current {
                            PremiumPill(text: "Current", tint: .secondary)
                        }
                    }
                    Text(plan.tagline).font(.subheadline).foregroundStyle(.secondary)
                    if let reason = plan.recommendationReason {
                        Text(reason).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 6) {
                        Text(PremiumPricing.priceLine(plan, billing: billing))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
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
                    .foregroundStyle(selected ? plan.tint : Color.secondary.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(ModulaPressStyle(scale: 0.98))
        .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: true, tint: selected ? plan.tint.opacity(0.4) : nil, specular: selected)
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(plan.tint.opacity(0.85), lineWidth: 1.5)
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
    var action: () -> Void

    private var label: String {
        if currentPlan == plan { return "You’re on \(plan.shortTitle)" }
        return comingSoon ? "\(plan.shortTitle) · \(PremiumPricing.comingSoon)" : "Continue with \(plan.shortTitle)"
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Capsule())
        }
        .buttonStyle(ModulaPressStyle(scale: 0.97))
        .modulaGlass(in: Capsule(), interactive: true, tint: plan.tint, prominent: true, specular: true)
        .disabled(currentPlan == plan || comingSoon)
        .opacity(comingSoon ? 0.6 : 1)
        .accessibilityIdentifier("premium.continue")
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
                Text("Local preview only. Never saved to your account or sent to Modula. No purchases exist yet.")
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
