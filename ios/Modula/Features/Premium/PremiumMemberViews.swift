import SwiftUI

// MARK: - Dashboard

struct PremiumDashboardView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var store = PremiumEntitlementStore.shared
    @State private var accountNote: String?

    var body: some View {
        SettingsScrollCanvas {
            PremiumSceneHeader(scene: .unitLake)
            HStack(alignment: .center, spacing: 14) {
                if let asset = PremiumBadgeAsset.profileMark(for: store.plan) {
                    PremiumBadgeImage(asset: asset, size: 72)
                } else {
                    ModulaUnitMark(style: .glass()).frame(width: 72, height: 72)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.isPreviewing ? "Preview" : "Your plan")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(app.appearance.liveAccent)
                    Text(store.plan.title).font(.title2.weight(.bold))
                    Text(PremiumPricing.priceLine(store.plan, billing: store.selectedBilling))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Text(statusLine).font(.subheadline).foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                dashboardCard("Visitor insights", "Coming soon", "chart.bar") { open(.visitors) }
                dashboardCard("Storage", "\(store.plan.storageGB) GB in the catalogue", "internaldrive") { open(.storage) }
                dashboardCard("Premium badge", store.plan.shortTitle, "seal") { open(.badge) }
                dashboardCard("In-Mail", "Coming soon", "envelope") { open(.creator) }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("\(store.plan.shortTitle) includes").font(.headline)
                TelegramSettingsCard {
                    let included = PremiumFeature.allCases.filter { store.plan.includes($0.minimumPlan) }
                    if included.isEmpty {
                        Text("Core already includes today’s Modula. Premium only adds.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(16)
                    } else {
                        ForEach(Array(included.enumerated()), id: \.element.id) { index, feature in
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(app.appearance.liveAccent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.title).font(.subheadline.weight(.semibold))
                                    Text(catalogueLine(feature)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            if index < included.count - 1 { TelegramDivider() }
                        }
                    }
                }
            }

            Button { open(.manage) } label: {
                Text("Manage subscription")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(ModulaPressStyle(scale: 0.97))
            .modulaAccentCTA()
            .accessibilityIdentifier("premium.dashboard.manage")
            Button("Explore all features") { open(.features) }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
            if let accountNote {
                SettingsAPIFootnote(text: accountNote)
            }
            PremiumDisclaimerText()
        }
        .navigationTitle(store.plan.shortTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("premium.dashboard")
        .task { await refreshAccount() }
    }

    private var statusLine: String {
        if store.isPreviewing { return "Previewing \(store.plan.title) on this device. This is not a purchase." }
        return store.plan.isPaid ? "Paid plan on this device." : "You’re on Modula Core — free."
    }

    private func catalogueLine(_ feature: PremiumFeature) -> String {
        switch feature {
        case .inMail:
            return "\(store.plan.inMailCreditsPerMonth) a month in the catalogue. A live allowance is coming soon."
        case .profileVisitors:
            return store.plan.visitorHistoryDays == 0 ? "Not in this plan." : "\(store.plan.visitorHistoryDays)-day range in the catalogue. Coming soon."
        case .unlimitedModules:
            if let slots = store.plan.moduleSlots { return "Up to \(slots) modules in the catalogue." }
            return "No module cap in the catalogue."
        default:
            return feature.minimumPlan == store.plan ? "Included with \(store.plan.shortTitle)." : "Included."
        }
    }

    private func dashboardCard(_ title: String, _ detail: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol).foregroundStyle(app.appearance.liveAccent)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func open(_ route: PremiumSettingsRoute) {
        app.navigation.open(.settings(.premium(route)))
    }

    private func refreshAccount() async {
        guard app.auth.isSignedIn else {
            accountNote = "Sign in to load membership. The plan above is on this device."
            return
        }
        var notes: [String] = []
        do { try await PremiumRemote.loadMembership(client: app.client) }
        catch { notes.append("Membership couldn’t be refreshed.") }
        do { try await PremiumRemote.loadEntitlements(client: app.client) }
        catch { notes.append("Entitlements couldn’t be refreshed.") }
        notes.append("Membership and entitlements have no declared fields, so no server tier or usage is shown.")
        accountNote = notes.joined(separator: " ")
    }
}

// MARK: - Choose features

struct PremiumFeaturesView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var store = PremiumEntitlementStore.shared

    var body: some View {
        SettingsScrollCanvas {
            PremiumMasthead(
                eyebrow: store.selectedPlan.shortTitle.uppercased(),
                title: "Choose features",
                subtitle: "What’s in \(store.selectedPlan.title). Nothing here turns a feature on by itself."
            )
            Picker("Plan", selection: $store.selectedPlan) {
                ForEach(PremiumPlan.allCases) { Text($0.shortTitle).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("premium.features.plan")
            TelegramSettingsCard {
                ForEach(Array(PremiumFeature.allCases.enumerated()), id: \.element.id) { index, feature in
                    let included = store.selectedPlan.includes(feature.minimumPlan)
                    HStack(spacing: 12) {
                        Image(systemName: included ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(included ? app.appearance.liveAccent : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title).font(.subheadline.weight(.semibold))
                            Text(included ? "Included" : "From \(feature.minimumPlan.shortTitle)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                    if index < PremiumFeature.allCases.count - 1 { TelegramDivider() }
                }
            }
            Text("Limits in the plan catalogue are not live usage.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            PremiumDisclaimerText()
        }
        .navigationTitle("Choose features")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("premium.features")
    }
}

// MARK: - Manage

struct PremiumManageView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var store = PremiumEntitlementStore.shared
    @State private var confirming = false
    @State private var billingNote = "Payment method is coming soon."

    var body: some View {
        SettingsScrollCanvas {
            PremiumSceneHeader(scene: .sunrise)
            Text("Manage subscription").font(.largeTitle.weight(.bold)).frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text("Your plan").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(store.plan.title).font(.title3.weight(.semibold))
                Text(PremiumPricing.priceLine(store.plan, billing: store.selectedBilling))
                    .font(.subheadline.monospacedDigit())
                Text(store.isPreviewing ? "Preview on this device" : (store.plan.isPaid ? "On this device" : "No paid plan"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(app.appearance.liveAccent)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false, specular: true)

            TelegramSettingsCard {
                manageRow("Next billing date", "Coming soon", "calendar") {}
                TelegramDivider()
                manageRow("Payment method", "Coming soon", "creditcard") {}
                TelegramDivider()
                manageRow("Change plan", "Compare plans", "arrow.left.arrow.right") {
                    app.navigation.open(.settings(.premium(.compare)))
                }
                TelegramDivider()
                manageRow("Billing and invoices", "From your account", "doc.text") {
                    app.navigation.open(.settings(.monetisation(.invoices)))
                }
                TelegramDivider()
                manageRow("Badge visibility", "On your profile", "seal") {
                    app.navigation.open(.settings(.premium(.badge)))
                }
            }
            Text(billingNote).font(.footnote).foregroundStyle(.secondary)

            if store.plan.isPaid {
                Button {
                    confirming = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cancel subscription").font(.body.weight(.semibold))
                        Text("Nothing you own is deleted.").font(.caption)
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                .buttonStyle(.plain)
                .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true, tint: Color.red.opacity(0.2))
                .accessibilityIdentifier("premium.manage.cancel")
            }

            if confirming {
                VStack(alignment: .leading, spacing: 8) {
                    Text("If you moved to Core").font(.headline)
                    ForEach(PremiumDowngrade.outcomes(from: store.plan, to: .core, usage: PremiumUsage())) { outcome in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(outcome.title).font(.subheadline.weight(.semibold))
                            Text(outcome.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("Usage isn’t available, so this doesn’t list anything over a limit. Cancelling is coming soon. No request was sent.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("premium.manage.downgrade")
            }
            PremiumDisclaimerText()
        }
        .navigationTitle("Manage subscription")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("premium.manage")
        .task { await loadBilling() }
    }

    private func manageRow(_ title: String, _ subtitle: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 24).foregroundStyle(app.appearance.liveAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func loadBilling() async {
        guard app.auth.isSignedIn else { return }
        do {
            try await PremiumRemote.loadBillingAdapters(client: app.client)
            billingNote = "Billing adapters responded. No payment method is shown — that response has no declared fields. Coming soon."
        } catch {
            billingNote = "Payment method is coming soon."
        }
    }
}

// MARK: - Studio

struct PremiumStudioView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        SettingsScrollCanvas {
            PremiumSceneHeader(scene: .studio)
            PremiumBadgeImage(asset: .obsidian, size: 88)
                .frame(maxWidth: .infinity)
            Text("Built for businesses and teams.")
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Text(PremiumPricing.priceLine(.studio, billing: .monthly))
                .font(.headline.monospacedDigit())
                .frame(maxWidth: .infinity)
            Text("Give your team more room to connect and create. Seats and roles aren’t available yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            TelegramSettingsCard {
                ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row).font(.subheadline.weight(.semibold))
                            Text("Coming soon").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    if index < Self.rows.count - 1 { TelegramDivider() }
                }
            }
            Button {
                app.navigation.open(.settings(.help(.contact)))
            } label: {
                Text("Contact support")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(ModulaPressStyle(scale: 0.97))
            .modulaAccentCTA()
            PremiumDisclaimerText()
        }
        .navigationTitle("Studio")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("premium.studio")
    }

    private static let rows = [
        "Team seats and roles",
        "Shared inbox",
        "Team CRM",
        "Brand customisation",
        "Team analytics",
        "Dedicated support"
    ]
}

// MARK: - Storage

struct PremiumStorageView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var store = PremiumEntitlementStore.shared

    var body: some View {
        SettingsScrollCanvas {
            PremiumSceneHeader(scene: .storageCloud)
            Text("Storage & Files").font(.largeTitle.weight(.bold))
            Text("More room for what matters.").font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("\(store.plan.storageGB) GB")
                    .font(.largeTitle.weight(.bold).monospacedDigit())
                Text("Included in the \(store.plan.shortTitle) catalogue.")
                    .font(.subheadline)
                Text("How much you’ve used: Coming soon.")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false, specular: true)
            .accessibilityIdentifier("premium.storage.allowance")
            TelegramSettingsCard {
                ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, title in
                    HStack {
                        Text(title).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("Coming soon").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    if index < Self.rows.count - 1 { TelegramDivider() }
                }
            }
            Button("Explore storage plans") {
                app.navigation.open(.settings(.premium(.compare)))
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            SettingsAPIFootnote(text: "There is no storage-usage route, so used space, file lists and backups are not shown.")
        }
        .navigationTitle("Storage & Files")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("premium.storage")
    }

    private static let rows = ["Automatic backup", "Access on your devices", "Version history", "Large file support"]
}

// MARK: - Visitors

struct PremiumVisitorsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var insights: CreatorInsightsResponse?
    @State private var error: String?

    var body: some View {
        SettingsScrollCanvas {
            Text("Visitor insights").font(.largeTitle.weight(.bold)).frame(maxWidth: .infinity, alignment: .leading)
            Text("Who views your profile.").font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("Profile visitors").font(.headline)
                Text("Coming soon").font(.title2.weight(.semibold))
                Text("Profile views aren’t shown. Modula doesn’t estimate them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
            .accessibilityIdentifier("premium.visitors.soon")

            if let insights {
                Text("Activity that is counted").font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    SettingsStatChip(label: "Followers", value: insights.totals.followers.formatted(), symbol: "person.2")
                    SettingsStatChip(label: "New followers", value: insights.totals.newFollowers.formatted(), symbol: "person.badge.plus")
                    SettingsStatChip(label: "Likes & reactions", value: (insights.totals.likes + insights.totals.reactions).formatted(), symbol: "heart")
                    SettingsStatChip(label: "Comments", value: insights.totals.comments.formatted(), symbol: "bubble.left")
                }
                SettingsAPIFootnote(text: "From your posts and profile, excluding your own. Not tracked: \(CreatorInsightsView.untrackedLabel(insights.notTracked)).")
            } else if let error {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            } else if app.auth.isSignedIn {
                ProgressView()
            } else {
                Text("Sign in to load counted activity.").font(.footnote).foregroundStyle(.secondary)
            }
            Button("Open insights") { app.navigation.open(.settings(.creator(.insights))) }
                .font(.body.weight(.semibold))
                .frame(minHeight: 44)
        }
        .navigationTitle("Visitor insights")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("premium.visitors")
        .task { await load() }
    }

    private func load() async {
        guard app.auth.isSignedIn else { return }
        do {
            insights = try await PremiumRemote.loadInsights(client: app.client)
            error = nil
        } catch {
            if insights == nil { self.error = "Counted activity couldn’t be loaded. Profile visitors stay coming soon." }
        }
    }
}

// MARK: - Creator tools

struct PremiumCreatorView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        SettingsScrollCanvas {
            PremiumMasthead(
                eyebrow: "HORIZON PLUS",
                title: "Creator tools.",
                subtitle: "Create. Grow. Earn. Tools without a route say coming soon."
            )
            TelegramSettingsCard {
                creatorRow("Scheduled posts", true, nil)
                TelegramDivider()
                creatorRow("Creator subscriptions", true, nil)
                TelegramDivider()
                creatorRow("Storefront", true, nil)
                TelegramDivider()
                creatorRow("Advanced analytics", false, .settings(.creator(.insights)))
                TelegramDivider()
                creatorRow("Payouts", false, .settings(.monetisation(.payouts)))
                TelegramDivider()
                creatorRow("In-Mail", false, .messages(.inMail(.inbox)))
                TelegramDivider()
                creatorRow("Custom links", true, nil)
                TelegramDivider()
                creatorRow("Priority support", false, .settings(.help(.contact)))
                TelegramDivider()
                creatorRow("Content planning", true, nil)
            }
            PremiumDisclaimerText()
        }
        .navigationTitle("Creator tools")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("premium.creator")
    }

    private func creatorRow(_ title: String, _ soon: Bool, _ route: AppRoute?) -> some View {
        Button {
            if let route { app.navigation.open(route) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(soon ? "Coming soon" : "Opens the live screen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if route != nil {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(soon)
    }
}

// MARK: - More possibilities

struct PremiumPossibilitiesView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var store = PremiumEntitlementStore.shared

    var body: some View {
        SettingsScrollCanvas {
            PremiumMasthead(
                eyebrow: "PREMIUM",
                title: "More possibilities with Modula.",
                subtitle: "More reach. More room. More expression.",
                unit: .premiumGold
            )
            HStack(spacing: 10) {
                possibility(.core)
                possibility(.plus)
                possibility(.horizon)
            }
            Text("What you get").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                SettingsFeatureTile(title: "More storage", detail: "Up to \(PremiumPlan.horizon.storageGB) GB in the Horizon catalogue.", symbol: "internaldrive", tint: app.appearance.liveAccent)
                SettingsFeatureTile(title: "Premium tools", detail: "Modules, In-Mail and a membership mark.", symbol: "sparkles", tint: app.appearance.liveAccent)
                SettingsFeatureTile(title: "Deeper insights", detail: "Counted activity is live. Profile visitors are coming soon.", symbol: "chart.bar", tint: app.appearance.liveAccent)
                SettingsFeatureTile(title: "Priority support", detail: "Coming soon.", symbol: "headphones", tint: app.appearance.liveAccent)
            }
            Button {
                store.selectedPlan = .horizon
                app.navigation.open(.settings(.premium(.purchase)))
            } label: {
                VStack(spacing: 2) {
                    Text("Get Modula Horizon")
                    Text("\(PremiumPricing.priceLine(.horizon, billing: .monthly)) · Sandbox, nothing is charged")
                        .font(.caption)
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(ModulaPressStyle(scale: 0.97))
            .modulaAccentCTA()
            .accessibilityIdentifier("premium.possibilities.horizon")
            PremiumDisclaimerText()
        }
        .navigationTitle("More possibilities")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("premium.possibilities")
    }

    private func possibility(_ plan: PremiumPlan) -> some View {
        let current = store.plan == plan
        return VStack(alignment: .leading, spacing: 6) {
            if plan == .recommended {
                Text("Recommended").font(.caption2.weight(.semibold)).foregroundStyle(app.appearance.liveAccent)
            }
            Text(plan.shortTitle).font(.headline)
            Text(plan.isPaid ? PremiumPricing.priceLine(plan, billing: .monthly) : "Free")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(plan.tagline).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
            Spacer(minLength: 0)
            Button(current ? "Current plan" : (plan == .core ? "Core" : "View")) {
                store.selectedPlan = plan
                app.navigation.open(.settings(.premium(.compare)))
            }
            .font(.caption.weight(.semibold))
            .disabled(current && plan == .core)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .modulaGlass(
            in: RoundedRectangle(cornerRadius: 18, style: .continuous),
            interactive: false,
            tint: plan == .recommended ? app.appearance.liveAccent.opacity(0.35) : nil,
            specular: plan == .recommended
        )
    }
}

struct PremiumSceneHeader: View {
    var scene: ShellScene

    var body: some View {
        ShellSceneImage(scene: scene)
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}
