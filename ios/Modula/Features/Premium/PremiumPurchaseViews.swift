import Observation
import StoreKit
import SwiftUI

enum PremiumStoreKitConfiguration {
    static let configurationName = "ModulaPremium.storekit"
    static let productSource = "GreenField confirmed sandbox mapping"
    static let localConfigurationIsAppleSandboxEvidence = false
}

enum PremiumPurchaseCopy {
    static let sandbox = "Apple Sandbox purchases don’t charge your payment method."
    static let welcomeTitle = "You’re Premium!"
}

enum PremiumPurchasePhase: Equatable {
    case idle, loadingProducts, ready, purchasing, pending, restoring, succeeded

    var busy: Bool {
        self == .loadingProducts || self == .purchasing || self == .restoring
    }
}

enum PremiumStoreKitError: Error, LocalizedError {
    case signedOut
    case mappingUnavailable
    case productUnavailable
    case unverified
    case accountMismatch
    case serverMismatch

    var errorDescription: String? {
        switch self {
        case .signedOut: "Sign in to Modula before purchasing."
        case .mappingUnavailable: "Apple Sandbox products are not configured for this QA environment."
        case .productUnavailable: "The selected product is not available from the App Store."
        case .unverified: "StoreKit could not verify this transaction on the device."
        case .accountMismatch: "This transaction belongs to a different Modula account."
        case .serverMismatch: "GreenField rejected the verified transaction details."
        }
    }
}

/// StoreKit never grants Premium locally. GreenField accepts the Apple JWS and its
/// refreshed membership projection is the only source that changes feature access.
@MainActor
@Observable
final class PremiumStoreKitController {
    private let client: GreenfieldClient
    private var accountID: String?
    private var context: PremiumApplePurchaseContext?
    private var storeProducts: [String: Product] = [:]
    private var updatesTask: Task<Void, Never>?

    private(set) var phase: PremiumPurchasePhase = .idle
    private(set) var message: String?

    init(client: GreenfieldClient) {
        self.client = client
        updatesTask = Task { [weak self] in await self?.listenForTransactions() }
    }

    func setAccountID(_ value: String?) {
        guard value != accountID else { return }
        accountID = value
        context = nil
        storeProducts = [:]
        phase = .idle
        message = nil
        PremiumEntitlementStore.shared.setDebugOverride(nil)
        PremiumEntitlementStore.shared.resetServerState()
        if value != nil {
            Task { [weak self] in await self?.refreshMembership() }
        }
    }

    func prepare() async {
        guard accountID != nil else {
            phase = .idle
            message = PremiumStoreKitError.signedOut.localizedDescription
            return
        }
        phase = .loadingProducts
        do {
            try await loadContextAndProducts()
            phase = .ready
            message = nil
        } catch {
            phase = .idle
            message = Self.message(error)
        }
    }

    func productID(plan: PremiumPlan, billing: PremiumBilling) -> String? {
        context?.product(plan: plan, billing: billing)?.productID
    }

    func displayPrice(plan: PremiumPlan, billing: PremiumBilling) -> String? {
        guard let productID = productID(plan: plan, billing: billing) else { return nil }
        return storeProducts[productID]?.displayPrice
    }

    func purchase(plan: PremiumPlan, billing: PremiumBilling) async -> Bool {
        guard !phase.busy else { return false }
        phase = .purchasing
        message = nil
        do {
            try await ensurePrepared()
            guard let context, let mapping = context.product(plan: plan, billing: billing) else {
                throw PremiumStoreKitError.mappingUnavailable
            }
            guard let product = storeProducts[mapping.productID], product.type == .autoRenewable else {
                throw PremiumStoreKitError.productUnavailable
            }
            switch try await product.purchase(options: [.appAccountToken(context.appAccountToken)]) {
            case .success(let verification):
                let accepted = try await completePurchase(
                    verification,
                    mapping: mapping,
                    accountToken: context.appAccountToken
                )
                phase = .succeeded
                message = accepted.replay ? "Purchase restored and verified by GreenField." : "Purchase verified by GreenField."
                return true
            case .pending:
                phase = .pending
                message = "The purchase is pending Apple approval. Premium remains unchanged."
            case .userCancelled:
                phase = .ready
                message = "Purchase cancelled. Nothing changed."
            @unknown default:
                phase = .ready
                message = "StoreKit returned an unsupported purchase state. Nothing changed."
            }
        } catch {
            phase = .ready
            message = Self.message(error)
        }
        return false
    }

    /// `AppStore.sync()` is intentionally called only from this explicit user action.
    func restore() async -> Bool {
        guard !phase.busy else { return false }
        phase = .restoring
        message = nil
        do {
            try await ensurePrepared()
            guard let context else { throw PremiumStoreKitError.mappingUnavailable }
            try await AppStore.sync()
            var submitted = 0
            for await verification in Transaction.currentEntitlements {
                guard case .verified(let transaction) = verification,
                      let mapping = context.products.first(where: { $0.productID == transaction.productID }) else { continue }
                // A device may hold purchases for more than one Modula account.
                // Never submit or finish evidence bound to a different account.
                guard transaction.appAccountToken == context.appAccountToken else { continue }
                _ = try await acceptAndFinish(verification, transaction: transaction, mapping: mapping)
                submitted += 1
            }
            try await refreshMembershipThrowing()
            phase = .succeeded
            message = submitted == 0
                ? "StoreKit sync finished. GreenField found no active Premium purchase for this account."
                : "Restored \(submitted) Apple transaction\(submitted == 1 ? "" : "s") through GreenField."
            return true
        } catch {
            phase = .ready
            message = Self.message(error)
            return false
        }
    }

    func refreshMembership() async {
        do {
            try await refreshMembershipThrowing()
        } catch {
            message = Self.message(error)
        }
    }

    private func ensurePrepared() async throws {
        guard accountID != nil else { throw PremiumStoreKitError.signedOut }
        if context == nil || storeProducts.isEmpty { try await loadContextAndProducts() }
    }

    private func loadContextAndProducts() async throws {
        let context = try await PremiumRemote.applePurchaseContext(client: client)
        let products = try await Product.products(for: context.products.map(\.productID))
        let available = products.filter { $0.type == .autoRenewable }
        guard !available.isEmpty else { throw PremiumStoreKitError.productUnavailable }
        self.context = context
        storeProducts = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
    }

    private func acceptAndFinish(
        _ verification: VerificationResult<Transaction>,
        transaction: Transaction,
        mapping: PremiumAppleProductMapping
    ) async throws -> PremiumAppleTransactionResult {
        let accepted = try await PremiumRemote.submitAppleTransaction(verification.jwsRepresentation, client: client)
        guard accepted.productID == mapping.productID, accepted.plan == mapping.plan,
              accepted.transactionID == String(transaction.id) else {
            throw PremiumStoreKitError.serverMismatch
        }
        try await refreshMembershipThrowing()
        await transaction.finish()
        return accepted
    }

    private func completePurchase(
        _ verification: VerificationResult<Transaction>,
        mapping: PremiumAppleProductMapping,
        accountToken: UUID
    ) async throws -> PremiumAppleTransactionResult {
        guard case .verified(let transaction) = verification else {
            throw PremiumStoreKitError.unverified
        }
        guard transaction.productID == mapping.productID,
              transaction.appAccountToken == accountToken else {
            throw PremiumStoreKitError.accountMismatch
        }
        let accepted = try await acceptAndFinish(verification, transaction: transaction, mapping: mapping)
        guard accepted.status == .active || accepted.status == .grace else {
            throw PremiumStoreKitError.serverMismatch
        }
        return accepted
    }

    private func refreshMembershipThrowing() async throws {
        guard let accountID else { throw PremiumStoreKitError.signedOut }
        let membership = try await PremiumRemote.loadMembership(client: client)
        guard membership.accountID == accountID else { throw PremiumStoreKitError.accountMismatch }
        try await PremiumRemote.loadEntitlements(client: client)
        PremiumEntitlementStore.shared.apply(membership)
        PremiumEntitlementStore.shared.setDebugOverride(nil)
    }

    private func listenForTransactions() async {
        for await verification in Transaction.updates {
            guard !Task.isCancelled else { return }
            guard case .verified(let transaction) = verification, accountID != nil else { continue }
            do {
                try await ensurePrepared()
                guard let context,
                      let mapping = context.products.first(where: { $0.productID == transaction.productID }),
                      transaction.appAccountToken == context.appAccountToken else {
                    throw PremiumStoreKitError.accountMismatch
                }
                _ = try await acceptAndFinish(verification, transaction: transaction, mapping: mapping)
                phase = .succeeded
                message = "Apple updated your subscription. GreenField verified the change."
            } catch {
                // Do not finish an unaccepted transaction. StoreKit can deliver it again
                // after sign-in, network recovery, or server configuration repair.
                message = Self.message(error)
            }
        }
    }

    private static func message(_ error: Error) -> String {
        if case APIError.rejected(_, let code) = error {
            return "GreenField did not verify the Apple transaction (\(code)). Premium remains unchanged."
        }
        return (error as? LocalizedError)?.errorDescription ?? "Apple Sandbox is unavailable. Premium remains unchanged."
    }
}

struct PremiumPurchaseView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var store = PremiumEntitlementStore.shared

    var body: some View {
        SettingsScrollCanvas {
            Text("APPLE SANDBOX")
                .font(.caption.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(app.appearance.liveAccent)
                .frame(maxWidth: .infinity)
            if let asset = PremiumBadgeAsset.profileMark(for: store.selectedPlan) {
                PremiumBadgeImage(asset: asset, size: 96).frame(maxWidth: .infinity)
            }
            Text(store.selectedPlan.title).font(.largeTitle.weight(.bold)).frame(maxWidth: .infinity)
            Text(app.premiumPurchases.displayPrice(plan: store.selectedPlan, billing: store.selectedBilling) ?? "Unavailable")
                .font(.title3.weight(.semibold).monospacedDigit())
                .frame(maxWidth: .infinity)
            if let id = app.premiumPurchases.productID(plan: store.selectedPlan, billing: store.selectedBilling) {
                Text(id).font(.caption.monospaced()).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
            Text(PremiumPurchaseCopy.sandbox)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Products come from GreenField’s confirmed App Store Connect mapping. The bundled StoreKit file is local-test data, not Apple sandbox evidence.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await purchase() }
            } label: {
                Text(purchaseTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(ModulaPressStyle(scale: 0.97))
            .modulaAccentCTA()
            .disabled(app.premiumPurchases.phase.busy || !store.selectedPlan.isPaid)
            .accessibilityIdentifier("premium.purchase.confirm")
            Button("Restore purchases") {
                Task { _ = await app.premiumPurchases.restore() }
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .disabled(app.premiumPurchases.phase.busy)
            .accessibilityIdentifier("premium.purchase.restore")
            if let message = app.premiumPurchases.message {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
            PremiumDisclaimerText()
        }
        .navigationTitle("Sandbox")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("premium.purchase")
        .task { await app.premiumPurchases.prepare() }
    }

    private var purchaseTitle: String {
        switch app.premiumPurchases.phase {
        case .loadingProducts: "Loading Apple products…"
        case .purchasing: "Waiting for Apple…"
        case .restoring: "Restoring…"
        case .pending: "Pending Apple approval"
        default: store.selectedPlan.isPaid ? "Continue with Apple Sandbox" : "Choose a paid plan"
        }
    }

    private func purchase() async {
        guard store.selectedPlan.isPaid else {
            app.navigation.open(.settings(.premium(.compare)))
            return
        }
        if await app.premiumPurchases.purchase(plan: store.selectedPlan, billing: store.selectedBilling) {
            app.navigation.open(.settings(.premium(.welcome)))
        }
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
            Text(welcomeDetail)
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

    private var welcomeDetail: String {
        if store.isPreviewing { return "\(store.plan.title) is previewing on this device." }
        if store.entitlement.source == .serverVerified {
            return "GreenField verified your Apple Sandbox membership: \(store.plan.title)."
        }
        return "You’re on \(store.plan.title)."
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
