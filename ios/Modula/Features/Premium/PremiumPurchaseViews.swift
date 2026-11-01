import SwiftUI

// MARK: - Local StoreKit configuration
//
// `ModulaPremium.storekit` lists the same catalogue prices for a local StoreKit test.
// This app never calls `Product.purchase` or `SKPaymentQueue`. Nothing is charged.

enum PremiumStoreKitLocal {
    static let configurationName = "ModulaPremium.storekit"
    static let livePurchases = false

    static func productID(plan: PremiumPlan, billing: PremiumBilling) -> String? {
        guard plan.isPaid else { return nil }
        return "modula.premium.\(plan.rawValue).\(billing.rawValue)"
    }
}

enum PremiumPurchaseCopy {
    static let sandbox = "Nothing is charged. This is a local sandbox preview."
    static let welcomeTitle = "You’re Premium!"
}

struct PremiumPurchaseView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var store = PremiumEntitlementStore.shared
    @State private var message: String?

    var body: some View {
        SettingsScrollCanvas {
            Text("Sandbox")
                .font(.caption.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(app.appearance.liveAccent)
                .frame(maxWidth: .infinity)
            if let asset = PremiumBadgeAsset.profileMark(for: store.selectedPlan) {
                PremiumBadgeImage(asset: asset, size: 96).frame(maxWidth: .infinity)
            }
            Text(store.selectedPlan.title).font(.largeTitle.weight(.bold)).frame(maxWidth: .infinity)
            Text(PremiumPricing.priceLine(store.selectedPlan, billing: store.selectedBilling))
                .font(.title3.weight(.semibold).monospacedDigit())
                .frame(maxWidth: .infinity)
            if let id = PremiumStoreKitLocal.productID(plan: store.selectedPlan, billing: store.selectedBilling) {
                Text(id).font(.caption.monospaced()).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            Text(PremiumPurchaseCopy.sandbox)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("\(PremiumStoreKitLocal.configurationName) is local configuration only. No payment sheet is started.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                confirmSandbox()
            } label: {
                Text(store.selectedPlan.isPaid ? "Continue in sandbox" : "Choose a paid plan")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(ModulaPressStyle(scale: 0.97))
            .modulaAccentCTA()
            .accessibilityIdentifier("premium.purchase.confirm")
            if let message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
            PremiumDisclaimerText()
        }
        .navigationTitle("Sandbox")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("premium.purchase")
    }

    private func confirmSandbox() {
        guard store.selectedPlan.isPaid else {
            app.navigation.open(.settings(.premium(.compare)))
            return
        }
        store.setDebugOverride(store.selectedPlan)
        guard store.plan == store.selectedPlan else {
            message = "This build can’t preview a plan."
            return
        }
        app.navigation.open(.settings(.premium(.welcome)))
    }
}

struct PremiumWelcomeView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var store = PremiumEntitlementStore.shared

    var body: some View {
        SettingsScrollCanvas {
            PremiumSceneHeader(scene: .sunrise)
            if let asset = PremiumBadgeAsset.profileMark(for: store.plan) {
                PremiumBadgeImage(asset: asset, size: 108).frame(maxWidth: .infinity)
            }
            Text(PremiumPurchaseCopy.welcomeTitle)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Text(store.isPreviewing ? "\(store.plan.title) is previewing on this device." : "You’re on \(store.plan.title). Nothing was charged.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(PremiumPurchaseCopy.sandbox)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
            Button {
                app.navigation.open(.settings(.premium(.profile)))
            } label: {
                Text("Your Premium profile")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(ModulaPressStyle(scale: 0.97))
            .modulaAccentCTA()
            Button("Premium settings") { app.navigation.open(.settings(.premium(.settings))) }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
            PremiumDisclaimerText()
        }
        .navigationTitle("You’re Premium")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("premium.welcome")
    }
}

struct PremiumProfilePreviewView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var store = PremiumEntitlementStore.shared
    @State private var verificationNote = "Verification is separate and cannot be bought."

    private var profile: ModulaProfile? { app.profile.ownProfile }

    private var name: String {
        profile?.displayName
            ?? app.auth.account?.displayName
            ?? app.auth.account?.primaryHandle
            ?? "Your profile"
    }

    private var handle: String? { profile?.handle ?? app.auth.account?.primaryHandle }

    var body: some View {
        SettingsScrollCanvas {
            if let profile, profile.coverURL != nil || profile.coverColour != nil {
                Text("Cover and photo come from your profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                ModulaAvatar(initials: profile?.initials ?? initials(name), url: profile?.avatarURL, size: 72, name: name)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(name).font(.title3.weight(.semibold)).lineLimit(2)
                        if store.showsOwnBadge {
                            PremiumProfileBadge(plan: store.plan, size: 22)
                        }
                    }
                    if let handle {
                        Text("@\(handle)").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if let profile {
                HStack {
                    count("Posts", profile.postCount)
                    count("Followers", profile.followerCount)
                    count("Following", profile.followingCount)
                }
                if let joined = profile.joinedAt {
                    Text("Joined \(joined.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Open your profile once to load posts and followers. They aren’t estimated here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(verificationNote).font(.footnote).foregroundStyle(.secondary)
            if profile?.isVerified == true {
                Text("This profile is verified. That check is not Premium.")
                    .font(.footnote.weight(.semibold))
            }
            Button("Edit profile") { app.navigation.open(.me(.edit)) }
                .font(.body.weight(.semibold))
                .frame(minHeight: 44)
            PremiumDisclaimerText()
        }
        .navigationTitle("Your Premium profile")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("premium.profile")
        .task { await loadVerification() }
    }

    private func count(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text(value.formatted()).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 { return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased() }
        return String(name.prefix(2)).uppercased()
    }

    private func loadVerification() async {
        guard app.auth.isSignedIn else { return }
        do {
            try await PremiumRemote.loadVerification(client: app.client)
            verificationNote = "Verification was requested separately. It is not part of this membership, and the response has no declared fields to show."
        } catch {
            verificationNote = "Verification couldn’t be loaded. It is still separate from Premium and cannot be bought."
        }
    }
}

struct PremiumMemberSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var store = PremiumEntitlementStore.shared

    var body: some View {
        SettingsScrollCanvas {
            Text("Premium settings").font(.largeTitle.weight(.bold))
            Text(store.plan.title).font(.headline).foregroundStyle(.secondary)
            TelegramSettingsCard {
                TelegramRow(title: "Badge", symbol: "seal.fill", tint: app.appearance.liveAccent, value: store.badgeVisible ? "Shown" : "Hidden") {
                    app.navigation.open(.settings(.premium(.badge)))
                }
                TelegramDivider()
                TelegramRow(title: "Manage subscription", symbol: "creditcard", tint: app.appearance.liveAccent) {
                    app.navigation.open(.settings(.premium(.manage)))
                }
                TelegramDivider()
                TelegramRow(title: "Payment method", symbol: "creditcard", tint: .secondary, value: "Coming soon") {}
            }
            Text("Payment method is coming soon. Hiding the badge never removes features.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let next = Self.upsell(from: store.plan) {
                Button("See \(next.shortTitle)") {
                    store.selectedPlan = next
                    app.navigation.open(.settings(.premium(.upsell)))
                }
                .font(.body.weight(.semibold))
                .frame(minHeight: 44)
            }
            PremiumDisclaimerText()
        }
        .navigationTitle("Premium settings")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("premium.settings")
    }

    static func upsell(from plan: PremiumPlan) -> PremiumPlan? {
        switch plan {
        case .core, .plus: .horizon
        case .horizon: .horizonPlus
        case .horizonPlus: .studio
        case .studio: nil
        }
    }
}

struct PremiumUpsellView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var store = PremiumEntitlementStore.shared

    private var target: PremiumPlan {
        PremiumMemberSettingsView.upsell(from: store.plan) ?? .horizon
    }

    var body: some View {
        SettingsScrollCanvas {
            Text(target.shortTitle.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.6)
                .foregroundStyle(app.appearance.liveAccent)
            Text(target.title).font(.largeTitle.weight(.bold))
            Text(target.tagline).font(.body).foregroundStyle(.secondary)
            if let reason = target.recommendationReason {
                Text(reason).font(.subheadline).foregroundStyle(.secondary)
            }
            Text(PremiumPricing.priceLine(target, billing: store.selectedBilling))
                .font(.title3.weight(.semibold).monospacedDigit())
            Text("No countdown and no scarcity. You can stay on \(store.plan.shortTitle).")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button {
                store.selectedPlan = target
                app.navigation.open(.settings(.premium(.purchase)))
            } label: {
                Text("Preview \(target.shortTitle) in sandbox")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(ModulaPressStyle(scale: 0.97))
            .modulaAccentCTA()
            .accessibilityIdentifier("premium.upsell.preview")
            Button("Maybe later") { app.navigation.close() }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
            PremiumDisclaimerText()
        }
        .navigationTitle(target.shortTitle)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("premium.upsell")
    }
}
