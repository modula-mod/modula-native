import SwiftUI

// MARK: - Shared chrome

enum PremiumAudience: String, CaseIterable, Identifiable {
    case personal, business
    var id: String { rawValue }
    var title: String { self == .personal ? "Personal" : "Business" }
    /// Personal is the three individual plans. Business is Studio, so the picker stays short (Hick).
    var plans: [PremiumPlan] {
        self == .personal ? [.plus, .horizon, .horizonPlus] : [.studio]
    }
}

struct PremiumMasthead: View {
    var eyebrow: String
    var title: String
    var subtitle: String
    var unit: ModulaUnitMark.Style = .glass()
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        VStack(spacing: 12) {
            ModulaWordmark(height: 26)
            Text(eyebrow)
                .font(.caption2.weight(.semibold))
                .tracking(2.2)
                .foregroundStyle(app.appearance.accent.color)
            Text(title)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            ModulaUnitMark(style: unit)
                .frame(width: 132, height: 132)
                .padding(.top, 4)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
    }
}

struct PremiumDisclaimerText: View {
    var body: some View {
        Text(PremiumCatalog.membershipDisclaimer)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("premium.disclaimer")
    }
}

// MARK: - Compare

struct PremiumCompareView: View {
    @Environment(AppEnvironment.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = PremiumEntitlementStore.shared

    private let plans = PremiumPlan.allCases

    var body: some View {
        SettingsScrollCanvas {
            PremiumMasthead(
                eyebrow: "PREMIUM",
                title: "Compare plans",
                subtitle: "More ways to connect, create and be seen. Find the plan that’s right for you."
            )
            Picker("Billing", selection: $store.selectedBilling) {
                Text("Monthly").tag(PremiumBilling.monthly)
                Text(yearlyTitle).tag(PremiumBilling.annual)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("premium.comparePicker")

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    ForEach(PremiumCatalog.comparison) { row in
                        rowView(row)
                    }
                }
                .padding(.vertical, 8)
            }
            .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false, specular: true)
            .accessibilityIdentifier("premium.compare.table")

            Text("Everything in Core stays free. Premium only adds.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            PremiumPrimaryButton(
                plan: store.selectedPlan,
                currentPlan: store.plan,
                comingSoon: true,
                identifier: "premium.compare.choose"
            ) {}
            Text(PremiumPricing.placeholderNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
            PremiumDisclaimerText()
        }
        .navigationTitle("Compare plans")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("premium.compare")
    }

    private var yearlyTitle: String {
        let save = PremiumPricing.annualSaveUpTo
        return save > 0 ? "Yearly · \(save)%" : "Yearly"
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: 88, height: 1)
            ForEach(plans) { plan in
                Button {
                    withAnimation(ModulaMotion.animation(.selection, personality: app.appearance.motion, reduceMotion: reduceMotion)) {
                        store.selectedPlan = plan
                    }
                } label: {
                    VStack(spacing: 4) {
                        if plan == .recommended {
                            Text("Recommended")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(app.appearance.accent.color)
                        }
                        Text(plan.shortTitle)
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        Text(headerPrice(plan))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(width: 84)
                    .padding(.vertical, 8)
                    .background(plan == store.selectedPlan ? app.appearance.accent.color.opacity(0.14) : Color.clear)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(plan == store.selectedPlan ? .isSelected : [])
            }
        }
    }

    private func headerPrice(_ plan: PremiumPlan) -> String {
        guard plan.isPaid else { return "Free" }
        switch store.selectedBilling {
        case .monthly:
            let from = plan.isPerSeat ? "from " : ""
            return "\(from)\(PremiumPricing.format(minor: plan.placeholderMonthlyMinor))"
        case .annual:
            return PremiumPricing.format(minor: plan.placeholderAnnualMinor)
        }
    }

    private func rowView(_ row: PremiumComparisonRow) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(row.area)
                .font(.caption.weight(.semibold))
                .frame(width: 88, alignment: .leading)
                .padding(.vertical, 8)
            ForEach(plans) { plan in
                Text(row.value(for: plan))
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .frame(width: 84, alignment: .center)
                    .padding(.vertical, 8)
                    .background(plan == store.selectedPlan ? app.appearance.accent.color.opacity(0.08) : Color.clear)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Horizon intro

struct PremiumIntroView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        SettingsScrollCanvas {
            PremiumMasthead(
                eyebrow: "HORIZON",
                title: "More reach. More room. More expression.",
                subtitle: "Modula Premium makes Modula bigger — more ways to connect, create and be seen, without changing what makes the free experience great.",
                unit: .premiumGold
            )
            ModulaGlassGroup(spacing: 8) {
                VStack(spacing: 0) {
                    ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                        PremiumIntroRow(symbol: row.symbol, title: row.title, detail: row.detail) {
                            app.navigation.open(.settings(.premium(.compare)))
                        }
                        if index < Self.rows.count - 1 { TelegramDivider() }
                    }
                }
                .padding(.horizontal, 4)
            }
            Button {
                app.navigation.open(.settings(.premium(.compare)))
            } label: {
                Text("Explore plans")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(ModulaPressStyle(scale: 0.97))
            .modulaGlass(in: Capsule(), interactive: true, tint: app.appearance.accent.color, prominent: true, specular: true)
            .accessibilityIdentifier("premium.intro.explore")
            Button("Maybe later") { app.navigation.close() }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("premium.intro.later")
            PremiumDisclaimerText()
        }
        .navigationTitle("Horizon")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("premium.intro")
    }

    /// Catalogue facts for Horizon, plus an honest coming-soon where the backend does not exist.
    private static let rows: [(symbol: String, title: String, detail: String)] = [
        ("envelope", "In-Mail to connect with anyone", "\(PremiumPlan.horizon.inMailCreditsPerMonth) credits a month on the Horizon catalogue. A live allowance isn’t available yet."),
        ("chart.bar", "\(PremiumPlan.horizon.visitorHistoryDays)-day visitor insights", "Coming soon. Profile visitors aren’t tracked."),
        ("shippingbox", "Unlimited modules", "Horizon removes the module cap. Modules you already installed stay."),
        ("person.crop.rectangle", "Premium profile customisation", "Profile plate and QR card styles are part of Horizon."),
        ("headphones", "Priority support", "Coming soon.")
    ]
}

private struct PremiumIntroRow: View {
    var symbol: String
    var title: String
    var detail: String
    var action: () -> Void
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(app.appearance.accent.color)
                    .frame(width: 32, height: 32)
                    .background(app.appearance.accent.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
