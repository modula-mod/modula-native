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
    var unit: ModulaUnitMark.Style = .glass(ModulaBrandPalette.lavenderDeep)
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        VStack(spacing: ModulaSpacing.sm) {
            ModulaWordmark(height: ModulaLayout.homeWordmarkHeight)
            Text(eyebrow)
                .font(.caption2.weight(.semibold))
                .tracking(2.2)
                .foregroundStyle(app.appearance.liveAccent)
            Text(title)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            // Hero: the Modula Unit resting on a lavender glass pedestal (never the ribbon logo).
            PremiumUnitStage(unit: unit)
                .padding(.top, ModulaSpacing.xxs)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The Modula Unit floating over a soft lavender glass pedestal (Horizon / Compare / Choose plan
/// references). Decorative only: hidden from VoiceOver. Reduce Motion keeps it still; Reduce
/// Transparency gets an opaque backdrop and pedestal via `modulaGlass`'s fallback.
struct PremiumUnitStage: View {
    var unit: ModulaUnitMark.Style = .glass(ModulaBrandPalette.lavenderDeep)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    @State private var floating = false

    private typealias Metrics = ModulaPremiumMetrics
    private var stageShape: RoundedRectangle { RoundedRectangle(cornerRadius: ModulaRadius.xl, style: .continuous) }

    var body: some View {
        ZStack(alignment: .bottom) {
            stageShape.fill(backdrop)
            VStack(spacing: -Metrics.pedestalHeight / 2) {
                ModulaUnitMark(style: unit)
                    .frame(width: Metrics.unitSize, height: Metrics.unitSize)
                    .shadow(color: ModulaBrandPalette.lavenderDeep.opacity(0.32), radius: ModulaSpacing.md, y: ModulaSpacing.xs)
                    .offset(y: -Metrics.pedestalLift - (floating ? Metrics.floatAmplitude : 0))
                    .zIndex(1)
                pedestal
            }
            .padding(.bottom, ModulaSpacing.lg)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.heroStageHeight)
        .clipShape(stageShape)
        .overlay(stageShape.strokeBorder(Color.white.opacity(reduceTransparency ? 0 : 0.35), lineWidth: 0.8))
        .accessibilityHidden(true)
        .onAppear { startFloating() }
        .onChange(of: reduceMotion) { _, _ in startFloating() }
    }

    /// Lavender mist in light mode, a deep lavender wash in dark mode; flat under Reduce Transparency.
    private var backdrop: LinearGradient {
        let top = scheme == .dark ? ModulaBrandPalette.lavenderDeep.opacity(0.28) : ModulaBrandPalette.lavenderMist
        let bottom = scheme == .dark ? ModulaBrandPalette.lavenderDeep.opacity(0.10) : ModulaBrandPalette.lavender.opacity(0.55)
        return LinearGradient(colors: reduceTransparency ? [top, top] : [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    private var pedestal: some View {
        ZStack {
            // Soft contact shadow under the disc.
            Ellipse()
                .fill(ModulaBrandPalette.lavenderDeep.opacity(0.18))
                .frame(width: Metrics.pedestalWidth, height: Metrics.pedestalHeight)
                .offset(y: ModulaSpacing.xxs)
                .blur(radius: reduceTransparency ? 0 : ModulaSpacing.xxs)
            // Glass disc the Unit rests on.
            Color.clear
                .frame(width: Metrics.pedestalWidth, height: Metrics.pedestalHeight)
                .modulaGlass(in: Ellipse(), interactive: false, tint: ModulaBrandPalette.lavender, specular: true)
        }
    }

    private func startFloating() {
        guard !reduceMotion else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { floating = false }
            return
        }
        withAnimation(.easeInOut(duration: Metrics.floatSeconds).repeatForever(autoreverses: true)) {
            floating = true
        }
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

            // Sticky first column: the feature names stay put while the plan columns scroll
            // horizontally, so no row is ever truncated off-screen.
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(width: Self.areaWidth, height: Self.headerHeight)
                    ForEach(PremiumCatalog.comparison) { row in
                        Text(row.area)
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                            .frame(width: Self.areaWidth, height: Self.rowHeight, alignment: .leading)
                    }
                }
                .padding(.leading, ModulaSpacing.sm)
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        ForEach(PremiumCatalog.comparison) { row in
                            rowView(row)
                        }
                    }
                }
                .modulaHorizontalEdgeFade()
            }
            .padding(.vertical, ModulaSpacing.xs)
            .modulaGlass(in: RoundedRectangle(cornerRadius: ModulaRadius.large, style: .continuous), interactive: false, tint: ModulaBrandPalette.lavender, specular: true)
            .accessibilityIdentifier("premium.compare.table")

            Text("Everything in Core stays free. Premium only adds.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            PremiumPrimaryButton(
                plan: store.selectedPlan,
                currentPlan: store.plan,
                comingSoon: false,
                identifier: "premium.compare.choose"
            ) {
                app.navigation.open(.settings(.premium(.purchase)))
            }
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

    private static let areaWidth = ModulaPremiumMetrics.compareAreaWidth
    private static let columnWidth = ModulaPremiumMetrics.compareColumnWidth
    private static let headerHeight = ModulaPremiumMetrics.compareHeaderHeight
    private static let rowHeight = ModulaPremiumMetrics.compareRowHeight

    private var header: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(plans) { plan in
                Button {
                    withAnimation(ModulaMotion.animation(.selection, personality: app.appearance.motion, reduceMotion: reduceMotion)) {
                        store.selectedPlan = plan
                    }
                } label: {
                    VStack(spacing: ModulaSpacing.xxs) {
                        if plan == .recommended {
                            // One labelled recommendation (Von Restorff), in the accent only.
                            Text("Recommended")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, ModulaSpacing.xs)
                                .padding(.vertical, ModulaSpacing.hairline)
                                .background(app.appearance.liveAccent, in: Capsule())
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
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
                    .frame(width: Self.columnWidth, height: Self.headerHeight)
                    .background(plan == store.selectedPlan ? app.appearance.liveAccent.opacity(0.14) : Color.clear)
                    .contentShape(Rectangle())
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
            ForEach(plans) { plan in
                Text(row.value(for: plan))
                    .font(.caption2)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)
                    .frame(width: Self.columnWidth, height: Self.rowHeight, alignment: .center)
                    .background(plan == store.selectedPlan ? app.appearance.liveAccent.opacity(0.08) : Color.clear)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.area)
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
                subtitle: "Modula Premium makes Modula bigger — more ways to connect, create and be seen, without changing what makes the free experience great."
            )
            ModulaGlassGroup(spacing: ModulaSpacing.xs) {
                VStack(spacing: 0) {
                    ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                        PremiumIntroRow(symbol: row.symbol, title: row.title, detail: row.detail) {
                            app.navigation.open(.settings(.premium(.compare)))
                        }
                        if index < Self.rows.count - 1 { TelegramDivider() }
                    }
                }
                .padding(.horizontal, ModulaSpacing.xxs)
                .padding(.vertical, ModulaSpacing.xxs)
                // Soft lavender glass card (Gestalt common region: the five benefits read as one group).
                .modulaGlass(in: RoundedRectangle(cornerRadius: ModulaRadius.large, style: .continuous), interactive: false, tint: ModulaBrandPalette.lavender, specular: true)
            }
            // The one solid accent CTA on the page (Von Restorff); full width in the thumb zone (Fitts).
            Button {
                app.navigation.open(.settings(.premium(.compare)))
            } label: {
                Text("Explore plans")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: ModulaLayout.ctaHeight)
                    .contentShape(Capsule())
            }
            .buttonStyle(ModulaPressStyle(scale: 0.97))
            .modulaAccentCTA()
            .accessibilityIdentifier("premium.intro.explore")
            Button("Maybe later") { app.navigation.close() }
                .font(.body.weight(.semibold))
                .foregroundStyle(app.appearance.liveAccent)
                .frame(maxWidth: .infinity, minHeight: ModulaLayout.minimumTouch)
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
            HStack(spacing: ModulaSpacing.sm) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(app.appearance.liveAccent)
                    .frame(width: ModulaLayout.listRowIconWidth + ModulaSpacing.xxs, height: ModulaLayout.listRowIconWidth + ModulaSpacing.xxs)
                    .background(app.appearance.liveAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: ModulaRadius.small, style: .continuous))
                VStack(alignment: .leading, spacing: ModulaSpacing.hairline) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: ModulaSpacing.xs)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, ModulaSpacing.sm)
            .padding(.horizontal, ModulaSpacing.xs)
            .frame(minHeight: ModulaLayout.listRowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
