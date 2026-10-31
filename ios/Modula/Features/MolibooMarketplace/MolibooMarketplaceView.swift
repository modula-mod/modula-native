import SwiftUI
import UIKit

// Series 2 marketplace. Local registry and installed packs only.
// Greenfield has no Moliboo or marketplace route (HTTP atlas, 484 application routes), so nothing here
// is loaded from the network, priced, or sold. Purchases stay disabled.

enum MolibooMarketplaceTab: String, CaseIterable, Identifiable, Sendable {
    case discover, families, stickers, marketplace
    var id: String { rawValue }
    var title: String {
        switch self {
        case .discover: "Discover"
        case .families: "Families"
        case .stickers: "Stickers"
        case .marketplace: "Marketplace"
        }
    }
}

/// What the marketplace is allowed to claim. There is no server catalogue.
enum MolibooMarketplaceFacts {
    static let purchaseTitle = "Coming soon"
    static let purchaseReason = "Nothing is for sale. Greenfield has no Moliboo marketplace yet."
    static let stickersReason = "Moliboo stickers are not available. This screen does not load another sticker catalogue."
    static let extrasReason = "Limited editions and creator listings are not in this catalogue. Series 2 characters are Modula house drafts."

    static func drafts(in registry: MolibooCharacterRegistry) -> [MolibooRegistryCharacter] {
        registry.characters.filter { $0.availability == "draft" && !$0.purchasable }
    }

    static func families(in registry: MolibooCharacterRegistry) -> [MolibooRegistryFamily] {
        registry.families.filter { $0.series == 2 && $0.availability == "draft" }
    }

    static func showing(_ characters: [MolibooRegistryCharacter], family: String?, search: String, families: [MolibooRegistryFamily]) -> [MolibooRegistryCharacter] {
        MolibooCatalogueQuery.filter(characters, family: family, search: search, families: families)
    }
}

struct MolibooMarketplaceEntry: View {
    @State private var shown = false
    private var draftCount: Int {
        MolibooRegistryStore.bundled.map { MolibooMarketplaceFacts.drafts(in: $0).count } ?? 0
    }

    var body: some View {
        Button { shown = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "storefront")
                    .font(.body.weight(.semibold))
                    .frame(width: 34, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Marketplace").font(.subheadline.weight(.semibold))
                    Text("\(draftCount) Series 2 drafts · nothing for sale")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
        .accessibilityIdentifier("moliboo.marketplace.entry")
        .sheet(isPresented: $shown) { MolibooMarketplaceView() }
    }
}

struct MolibooMarketplaceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: MolibooMarketplaceTab = .discover
    @State private var family: String?
    @State private var search = ""
    @State private var path: [String] = []
    private let registry = MolibooRegistryStore.bundled

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let registry {
                    loaded(registry)
                } else {
                    ContentUnavailableView("Catalogue unavailable", systemImage: "questionmark.circle", description: Text("The Moliboo registry is not in this build."))
                }
            }
            .navigationTitle("Moliboos")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search drafts")
            .navigationDestination(for: String.self) { id in
                if let registry, let character = registry.character(id: id) {
                    MolibooMarketplaceDetail(character: character, family: registry.family(id: character.familyId))
                } else {
                    ContentUnavailableView("Moliboo unavailable", systemImage: "questionmark.circle")
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .accessibilityIdentifier("moliboo.marketplace")
    }

    private func loaded(_ registry: MolibooCharacterRegistry) -> some View {
        let drafts = MolibooMarketplaceFacts.drafts(in: registry)
        let families = MolibooMarketplaceFacts.families(in: registry)
        let shown = MolibooMarketplaceFacts.showing(drafts, family: family, search: search, families: families)
        return VStack(spacing: 0) {
            tabBar
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch tab {
                    case .discover:
                        discover(families, registry: registry)
                    case .families:
                        familySections(families, registry: registry)
                    case .stickers:
                        notice(MolibooMarketplaceFacts.stickersReason, symbol: "face.smiling")
                    case .marketplace:
                        marketplace(shown, families: families)
                    }
                }
                .padding(.vertical, 12)
            }
        }
        // Tab changes are instant. Reduce Motion has nothing to disable because this screen does not animate.
        .transaction { if reduceMotion { $0.disablesAnimations = true } }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ModulaGlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(MolibooMarketplaceTab.allCases) { item in
                        Button { tab = item } label: {
                            Text(item.title).font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .modulaGlass(in: Capsule(), interactive: true, tint: tab == item ? Color.accentColor.opacity(0.35) : nil)
                        .accessibilityAddTraits(tab == item ? .isSelected : [])
                        .accessibilityIdentifier("moliboo.marketplace.tab.\(item.rawValue)")
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
    }

    private func discover(_ families: [MolibooRegistryFamily], registry: MolibooCharacterRegistry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Series 2").font(.title2.weight(.bold)).padding(.horizontal, 16)
            Text("Ten families. Drafts only — nothing here can be bought.")
                .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 16)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(families) { family in
                    let count = registry.characters(in: family.id).count
                    Button { self.family = family.id; tab = .marketplace } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(family.name).font(.headline)
                            Text(rangeLabel(family)).font(.caption.monospaced()).foregroundStyle(.secondary)
                            Text("\(count) characters").font(.caption.weight(.semibold))
                            if let palette = family.palette {
                                Text(palette).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: true, tint: tint(family))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("moliboo.marketplace.family.\(family.id)")
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func familySections(_ families: [MolibooRegistryFamily], registry: MolibooCharacterRegistry) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(families) { family in
                VStack(alignment: .leading, spacing: 8) {
                    Text(family.name).font(.title3.weight(.bold))
                    Text("\(rangeLabel(family)) · \(registry.characters(in: family.id).count) characters")
                        .font(.caption).foregroundStyle(.secondary)
                    if let direction = family.artDirection {
                        Text(direction).font(.caption).foregroundStyle(.secondary)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(registry.characters(in: family.id)) { character in
                                characterCard(character, family: family)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func marketplace(_ shown: [MolibooRegistryCharacter], families: [MolibooRegistryFamily]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            familyChips(families)
            Text(MolibooMarketplaceFacts.extrasReason)
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
            Text("\(shown.count) drafts").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 16)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 12)], spacing: 12) {
                ForEach(shown) { character in
                    let family = families.first { $0.id == character.familyId }
                    characterCard(character, family: family)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func familyChips(_ families: [MolibooRegistryFamily]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ModulaGlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    chip("All", selected: family == nil) { family = nil }
                    ForEach(families) { item in
                        chip(item.label, selected: family == item.id) { family = item.id }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func characterCard(_ character: MolibooRegistryCharacter, family: MolibooRegistryFamily?) -> some View {
        Button { path.append(character.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                MolibooMarketplaceArtwork(character: character, tint: tint(family))
                    .frame(height: 96)
                Text("#\(character.catalogueNumber) · \(family?.label ?? character.familyId)")
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
                Text(character.name).font(.headline).lineLimit(1)
                Text(character.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text("Draft · \(MolibooMarketplaceFacts.purchaseTitle)")
                    .font(.caption2.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true, tint: tint(family))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(character.name), number \(character.number), draft, coming soon")
        .accessibilityIdentifier("moliboo.marketplace.\(character.key)")
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .modulaGlass(in: Capsule(), interactive: true, tint: selected ? Color.accentColor.opacity(0.35) : nil)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func notice(_ text: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Coming soon", systemImage: symbol).font(.headline)
            Text(text).font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .padding(.horizontal, 16)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
        .padding(.horizontal, 16)
        .accessibilityIdentifier("moliboo.marketplace.notice")
    }

    private func rangeLabel(_ family: MolibooRegistryFamily) -> String {
        guard family.range.count == 2 else { return family.label }
        return "\(family.range[0])–\(family.range[1])"
    }

    private func tint(_ family: MolibooRegistryFamily?) -> Color? {
        family?.accentHex.flatMap { Color(molibooHex: $0) }
    }
}

struct MolibooMarketplaceDetail: View {
    let character: MolibooRegistryCharacter
    let family: MolibooRegistryFamily?
    private var installedVersion: String? {
        MolibooPackageManager.shared.runtime.store.index(character.packageId).active
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MolibooMarketplaceArtwork(character: character, tint: family?.accentHex.flatMap { Color(molibooHex: $0) })
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .padding(12)
                    .modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false, tint: family?.accentHex.flatMap { Color(molibooHex: $0) })
                VStack(alignment: .leading, spacing: 4) {
                    Text("#\(character.catalogueNumber) · \(family?.name ?? character.familyId)")
                        .font(.subheadline.monospaced()).foregroundStyle(.secondary)
                    Text(character.name).font(.system(.title, design: .rounded).weight(.bold))
                    Text(character.title).font(.title3).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                if !character.traits.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(character.traits.enumerated()), id: \.offset) { _, trait in
                                Text(trait).font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .modulaGlass(in: Capsule(), interactive: false)
                            }
                        }
                    }
                }
                section("About") {
                    Text(character.personality.description).font(.body)
                    Text(character.personality.disclaimer).font(.caption).foregroundStyle(.secondary)
                }
                if let family {
                    section("Family") {
                        Text(family.name).font(.body.weight(.semibold))
                        if let direction = family.artDirection { Text(direction).font(.body) }
                        if let palette = family.palette { Text(palette).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                section("Artwork") {
                    if let installedVersion {
                        Text("Installed pack \(installedVersion). The portrait is the full image from that pack.")
                    } else {
                        Text("Not installed. The figure above is a placeholder until the on-demand pack is installed.")
                    }
                    Text(character.wearable ? "Wardrobe fits are not published for this draft." : "Not wearable while this character is a draft.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(action: {}) {
                    Text(MolibooMarketplaceFacts.purchaseTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .modulaGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: false)
                .disabled(true)
                .accessibilityIdentifier("moliboo.marketplace.purchase")
                .accessibilityHint(MolibooMarketplaceFacts.purchaseReason)
                Text(MolibooMarketplaceFacts.purchaseReason)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .navigationTitle(character.name)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("moliboo.marketplace.detail.\(character.key)")
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
    }
}

struct MolibooMarketplaceArtwork: View {
    let character: MolibooRegistryCharacter
    var tint: Color?
    private var store: MolibooPackageStore { MolibooPackageManager.shared.runtime.store }

    var body: some View {
        // Fit the whole portrait. A fill would crop it, and a cropped Moliboo is not shipped.
        if let data = store.activeMedia(packageId: character.packageId, path: "portrait.png"),
           let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("\(character.name) portrait")
        } else {
            MolibooDraftSilhouette(tint: tint ?? Color(red: 0.21, green: 0.61, blue: 0.67))
                .accessibilityLabel("\(character.name) placeholder")
        }
    }
}

/// A drawn stand-in. It is not a cropped image.
struct MolibooDraftSilhouette: View {
    var tint: Color

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.85))
            Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1.5)
            HStack(spacing: 10) {
                Circle().frame(width: 10, height: 10)
                Circle().frame(width: 10, height: 10)
            }
            .offset(y: -6)
            Capsule().frame(width: 18, height: 5).offset(y: 12)
        }
        .foregroundStyle(Color.primary.opacity(0.55))
        .padding(8)
    }
}
