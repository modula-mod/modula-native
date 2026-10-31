import SwiftUI

// MARK: - Badge pack
//
// Sixteen vector marks from the Premium badge pack, each a four-lobed Modula Unit.
// The profile mark follows the paid tier. It is never an identity-verification seal.

enum PremiumBadgeAsset: String, CaseIterable, Identifiable {
    case pearl = "PremiumBadgePearl"
    case horizon = "PremiumBadgeHorizon"
    case horizonPlus = "PremiumBadgeHorizonPlus"
    case obsidian = "PremiumBadgeObsidian"
    case crest = "PremiumBadgeCrest"
    case crown = "PremiumBadgeCrown"
    case frame = "PremiumBadgeFrame"
    case gift = "PremiumBadgeGift"
    case ticket = "PremiumBadgeTicket"
    case analytics = "PremiumBadgeAnalytics"
    case inMail = "PremiumBadgeInMail"
    case tokens = "PremiumBadgeTokens"
    case sparkle = "PremiumBadgeSparkle"
    case studio = "PremiumBadgeStudio"
    case nameplate = "PremiumBadgeNameplate"
    /// Pack artwork only. Not shown as a verification check.
    case memberMark = "PremiumBadgeMemberMark"

    var id: String { rawValue }

    /// The mark worn on a profile for this plan. Core has none.
    static func profileMark(for plan: PremiumPlan) -> PremiumBadgeAsset? {
        switch plan {
        case .core: nil
        case .plus: .pearl
        case .horizon: .horizon
        case .horizonPlus: .horizonPlus
        case .studio: .obsidian
        }
    }

    static let tierMarks: [PremiumBadgeAsset] = [.pearl, .horizon, .horizonPlus, .obsidian]

    var plan: PremiumPlan? {
        switch self {
        case .pearl: .plus
        case .horizon: .horizon
        case .horizonPlus: .horizonPlus
        case .obsidian: .studio
        default: nil
        }
    }

    var title: String {
        switch self {
        case .pearl: "Pearl"
        case .horizon: "Horizon"
        case .horizonPlus: "Horizon Plus"
        case .obsidian: "Obsidian"
        case .crest: "Crest"
        case .crown: "Crown"
        case .frame: "Profile frame"
        case .gift: "Gift"
        case .ticket: "Access ticket"
        case .analytics: "Analytics mark"
        case .inMail: "In-Mail"
        case .tokens: "Tokens"
        case .sparkle: "Creator spark"
        case .studio: "Studio emblem"
        case .nameplate: "Nameplate"
        case .memberMark: "Membership mark"
        }
    }

    /// Supporting artwork. Not a profile badge and not a live feature.
    static let gallery: [PremiumBadgeAsset] = [
        .crest, .crown, .frame, .inMail, .studio, .nameplate, .gift, .ticket, .analytics, .tokens, .sparkle, .memberMark
    ]
}

struct PremiumBadgeImage: View {
    let asset: PremiumBadgeAsset
    var size: CGFloat = 44

    var body: some View {
        Image(asset.rawValue)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel(asset.title)
    }
}

/// Small membership mark beside the profile name. The whole unit is shown, never cropped.
struct PremiumProfileBadge: View {
    let plan: PremiumPlan
    var size: CGFloat = 22

    var body: some View {
        if let asset = PremiumBadgeAsset.profileMark(for: plan) {
            PremiumBadgeImage(asset: asset, size: size)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(plan.shortTitle) membership")
                .accessibilityHint(PremiumCatalog.membershipDisclaimer)
                .accessibilityIdentifier("premium.badge.\(plan.rawValue)")
        }
    }
}

struct PremiumDestination: View {
    let route: PremiumSettingsRoute

    var body: some View {
        if PremiumFeatureFlags.premiumEnabled() {
            switch route {
            case .root:
                PremiumHubView()
            case .badge:
                PremiumBadgeSettingsView()
            case .compare:
                PremiumCompareView()
            case .intro:
                PremiumIntroView()
            case .dashboard:
                PremiumDashboardView()
            case .features:
                PremiumFeaturesView()
            case .manage:
                PremiumManageView()
            case .studio:
                PremiumStudioView()
            case .storage:
                PremiumStorageView()
            case .visitors:
                PremiumVisitorsView()
            case .creator:
                PremiumCreatorView()
            case .possibilities:
                PremiumPossibilitiesView()
            }
        } else {
            SettingsCapabilityUnavailableView(
                title: "Modula Premium",
                reason: "Premium isn’t available in this version.",
                symbol: "seal"
            )
        }
    }
}

struct PremiumBadgeSettingsView: View {
    @Environment(AppEnvironment.self) private var app
    @State private var store = PremiumEntitlementStore.shared
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        SettingsScrollCanvas {
            VStack(spacing: 10) {
                if let asset = PremiumBadgeAsset.profileMark(for: store.plan) {
                    PremiumBadgeImage(asset: asset, size: 96)
                    Text(asset.title).font(.title3.weight(.semibold))
                    Text("Shown on your profile for \(store.plan.title).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    ModulaUnitMark(style: .glass()).frame(width: 88, height: 88)
                    Text("Core has no membership mark.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("premium.badge.preview")

            SettingsToggleCard {
                Toggle("Show badge on profile", isOn: visibility)
                    .disabled(saving || !store.plan.showsBadge)
                    .accessibilityIdentifier("premium.badge.toggle")
            }
            Text(store.plan.showsBadge
                 ? "Hiding the mark never removes features."
                 : "A mark appears when a paid plan is active.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Marks by tier").font(.headline)
                HStack(spacing: 8) {
                    ForEach(PremiumBadgeAsset.tierMarks) { asset in
                        VStack(spacing: 6) {
                            PremiumBadgeImage(asset: asset, size: 56)
                            Text(asset.plan?.shortTitle ?? asset.title)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .modulaGlass(
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                            interactive: false,
                            tint: asset.plan == store.plan ? app.appearance.accent.color.opacity(0.35) : nil,
                            specular: asset.plan == store.plan
                        )
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(asset.title), \(asset.plan?.title ?? "")")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Artwork").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], spacing: 10) {
                    ForEach(PremiumBadgeAsset.gallery) { asset in
                        VStack(spacing: 6) {
                            PremiumBadgeImage(asset: asset, size: 48)
                            Text(asset.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(minHeight: 28, alignment: .top)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                    }
                }
                Text("These marks are artwork. They are not live counts, and the membership mark is not verification.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error {
                Text(error).font(.footnote).foregroundStyle(.red)
                    .accessibilityIdentifier("premium.badge.error")
            }
            Text(PremiumCatalog.membershipDisclaimer)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("premium.disclaimer")
        }
        .navigationTitle("Premium badge")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("premium.badge.settings")
    }

    private var visibility: Binding<Bool> {
        Binding(
            get: { store.badgeVisible },
            set: { value in Task { await setVisible(value) } }
        )
    }

    private func setVisible(_ visible: Bool) async {
        let previous = store.badgeVisible
        store.badgeVisible = visible
        guard app.auth.isSignedIn else { return }
        saving = true
        defer { saving = false }
        do {
            try await PremiumRemote.setBadgeVisible(visible, client: app.client)
            error = nil
        } catch {
            store.badgeVisible = previous
            self.error = SettingsRemoteError.message(error, fallback: "Couldn’t update the badge. Try again.")
        }
    }
}
