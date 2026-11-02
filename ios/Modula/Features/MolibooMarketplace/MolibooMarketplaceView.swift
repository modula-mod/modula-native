import SwiftUI
import UIKit

// Series 2 marketplace. The local registry preserves identities and the painted 2D presentation;
// GreenField supplies signed package discovery plus server-authoritative ownership/equipped state.

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

/// Stable Series 2 presentation facts. Installation and ownership state comes from GreenField.
enum MolibooMarketplaceFacts {
    static let purchaseTitle = "Install signed pack"
    static let purchaseReason = "Owned Moliboos install from GreenField as signed, data-only 2D content packs."
    static let stickersReason = "Sprout and Series sticker packs are discovered through GreenField; verified local art remains available offline."
    static let extrasReason = "Ownership is verified by GreenField. Installing a pack never grants ownership."

    static func drafts(in registry: MolibooCharacterRegistry) -> [MolibooRegistryCharacter] {
        registry.characters.filter { $0.availability == "draft" && !$0.purchasable }
    }

    static func families(in registry: MolibooCharacterRegistry) -> [MolibooRegistryFamily] {
        registry.families.filter { $0.series == 2 && $0.availability == "draft" }
    }

    @MainActor static func showing(_ characters: [MolibooRegistryCharacter], family: String?, search: String, families: [MolibooRegistryFamily]) -> [MolibooRegistryCharacter] {
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
                    Text("\(draftCount) Series 2 Moliboos · signed packs")
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
    @Environment(AppEnvironment.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tab: MolibooMarketplaceTab = .discover
    @State private var family: String?
    @State private var search = ""
    @State private var path: [String] = []
    @State private var detail: MolibooRegistryCharacter?
    @State private var toast: String?
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
            .navigationDestination(for: String.self) { id in
                if let registry, let fam = registry.family(id: id) {
                    MolibooFamilyCollection(family: fam, characters: registry.characters(in: fam.id)) { detail = $0 }
                } else {
                    ContentUnavailableView("Family unavailable", systemImage: "questionmark.circle")
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $detail) { character in
                NavigationStack {
                    MolibooMarketplaceDetail(character: character, family: registry?.family(id: character.familyId))
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { detail = nil } } }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast).font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .modulaGlass(in: Capsule(), interactive: false)
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .accessibilityIdentifier("moliboo.marketplace")
        .task {
            await MolibooPackageManager.shared.refreshCatalog()
            if app.auth.isSignedIn { await app.molibooOwnership.refresh() }
        }
    }

    private func flash(_ text: String) {
        toast = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            if toast == text { toast = nil }
        }
    }

    private func loaded(_ registry: MolibooCharacterRegistry) -> some View {
        let drafts = MolibooMarketplaceFacts.drafts(in: registry)
        let families = MolibooMarketplaceFacts.families(in: registry)
        let shown = MolibooMarketplaceFacts.showing(drafts, family: family, search: search, families: families)
        return VStack(spacing: 0) {
            tabBar
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch tab {
                    case .discover:
                        discover(drafts, families: families)
                    case .families:
                        familyBanners(families, registry: registry)
                    case .stickers:
                        MolibooStickerBrowser(notify: flash)
                    case .marketplace:
                        marketplace(shown, families: families)
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .transaction { if reduceMotion { $0.disablesAnimations = true } }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ModulaGlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(MolibooMarketplaceTab.allCases) { item in
                        Button { tab = item } label: {
                            Label(item.title, systemImage: item.symbol).font(.subheadline.weight(.semibold))
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

    // MARK: Discover

    private func discover(_ drafts: [MolibooRegistryCharacter], families: [MolibooRegistryFamily]) -> some View {
        let hero = drafts.first
        return VStack(alignment: .leading, spacing: 18) {
            MolibooHeroBanner(eyebrow: "SERIES 2 · \(drafts.count) NEW MOLIBOOS", title: "Discover\nMoliboos",
                              subtitle: "Ten new families, drawn live with the same rig as the originals.",
                              colors: [Color(red: 0.42, green: 0.72, blue: 0.98), Color(red: 0.78, green: 0.66, blue: 0.98)],
                              kind: hero?.kind, action: ("Explore", { tab = .marketplace }))
                .padding(.horizontal, 16)
            familyChips(families, onPick: { tab = .marketplace })
            sectionHeader("Meet the families", trailing: "\(families.count) families")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(families) { fam in
                        let members = drafts.filter { $0.familyId == fam.id }
                        Button { path.append(fam.id) } label: { familyTile(fam, members: members) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("moliboo.marketplace.family.\(fam.id)")
                    }
                }
                .padding(.horizontal, 16)
            }
            sectionHeader("New arrivals", trailing: "Signed content")
            grid(Array(drafts.prefix(8)), families: families)
        }
    }

    private func familyTile(_ fam: MolibooRegistryFamily, members: [MolibooRegistryCharacter]) -> some View {
        let c = MolibooFamilyStyle.color(fam)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: -18) {
                ForEach(Array(members.prefix(3).enumerated()), id: \.offset) { _, m in
                    if let k = m.kind { ModulaMascotFigure(kind: k, pose: .still(), size: 34).frame(width: 68, height: 64) }
                }
            }
            .frame(height: 64)
            Text(fam.name).font(.headline).foregroundStyle(.primary)
            Text(rangeLabel(fam)).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 176, alignment: .leading)
        .background(LinearGradient(colors: [c.opacity(0.32), c.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(c.opacity(0.35), lineWidth: 1))
    }

    // MARK: Families

    private func familyBanners(_ families: [MolibooRegistryFamily], registry: MolibooCharacterRegistry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(families) { fam in
                let members = registry.characters(in: fam.id)
                Button { path.append(fam.id) } label: {
                    MolibooHeroBanner(eyebrow: "\(fam.label.uppercased()) · \(rangeLabel(fam))", title: fam.name,
                                      subtitle: fam.artDirection ?? "\(members.count) characters",
                                      colors: MolibooFamilyStyle.gradient(fam), kind: members.first?.kind, action: nil, compact: true)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("moliboo.marketplace.familybanner.\(fam.id)")
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: Marketplace

    private func marketplace(_ shown: [MolibooRegistryCharacter], families: [MolibooRegistryFamily]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search Moliboos…", text: $search)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("moliboo.marketplace.search")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .modulaGlass(in: Capsule(), interactive: false)
            .padding(.horizontal, 16)
            familyChips(families, onPick: nil)
            HStack {
                Text("\(shown.count) Moliboos").font(.subheadline.weight(.semibold))
                Spacer()
                Label("Ownership verified", systemImage: "checkmark.shield").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            if shown.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                grid(shown, families: families)
            }
            Text(MolibooMarketplaceFacts.extrasReason)
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
        }
    }

    private func grid(_ characters: [MolibooRegistryCharacter], families: [MolibooRegistryFamily]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(characters) { character in
                Button { detail = character } label: {
                    MolibooMarketCard(character: character, family: families.first { $0.id == character.familyId })
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(character.name), number \(character.number), signed content pack")
                .accessibilityIdentifier("moliboo.marketplace.\(character.key)")
            }
        }
        .padding(.horizontal, 16)
    }

    private func familyChips(_ families: [MolibooRegistryFamily], onPick: (() -> Void)?) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", color: .pink, selected: family == nil) { family = nil; onPick?() }
                ForEach(families) { item in
                    chip(item.label, color: MolibooFamilyStyle.color(item), selected: family == item.id) { family = item.id; onPick?() }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ title: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(title).font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(color.opacity(selected ? 0.3 : 0.1), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(selected ? 0.9 : 0.3), lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func sectionHeader(_ title: String, trailing: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.bold))
            Spacer()
            Text(trailing).font(.caption.weight(.semibold)).foregroundStyle(.pink)
        }
        .padding(.horizontal, 16)
    }

    private func rangeLabel(_ family: MolibooRegistryFamily) -> String {
        guard family.range.count == 2 else { return family.label }
        return "#\(family.range[0])–\(family.range[1])"
    }
}

// MARK: - Shared pieces

enum MolibooFamilyStyle {
    static func color(_ family: MolibooRegistryFamily?) -> Color {
        family?.accentHex.flatMap { Color(molibooHex: $0) } ?? Color(red: 0.21, green: 0.61, blue: 0.67)
    }
    static func gradient(_ family: MolibooRegistryFamily?) -> [Color] {
        let c = color(family)
        return [c.opacity(0.95), c.opacity(0.45)]
    }
}

extension MolibooMarketplaceTab {
    var symbol: String {
        switch self {
        case .discover: "sparkles"
        case .families: "square.grid.2x2"
        case .stickers: "face.smiling"
        case .marketplace: "storefront"
        }
    }
}

/// Banner with a big live figure (mockup 01 / 03).
struct MolibooHeroBanner: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let colors: [Color]
    let kind: ModulaMascotKind?
    let action: (String, () -> Void)?
    var compact = false

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(eyebrow).font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.85))
                Text(title).font(compact ? .title2.weight(.bold) : .largeTitle.weight(.bold)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.9)).lineLimit(3)
                if let action {
                    Button(action: action.1) {
                        Label(action.0, systemImage: "arrow.right").font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.white, in: Capsule()).foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let kind {
                ModulaMascotFigure(kind: kind, pose: MascotPose(t: 0.4, mood: .wave, amp: 1), size: compact ? 52 : 70)
                    .frame(width: compact ? 104 : 140, height: compact ? 99 : 133)
                    .accessibilityHidden(true)
            }
        }
        .padding(compact ? 16 : 20)
        .frame(minHeight: compact ? 130 : 190)
        .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .topTrailing) {
            ZStack {
                Circle().fill(.white.opacity(0.18)).frame(width: 14).offset(x: -40, y: 24)
                Circle().fill(.white.opacity(0.14)).frame(width: 9).offset(x: -96, y: 40)
                Circle().fill(.white.opacity(0.2)).frame(width: 6).offset(x: -24, y: 60)
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Rich card (mockup 01): tinted stage with the live figure, badge, number · family, name, title, state.
struct MolibooMarketCard: View {
    let character: MolibooRegistryCharacter
    let family: MolibooRegistryFamily?
    @Environment(AppEnvironment.self) private var app
    @State private var manager = MolibooPackageManager.shared

    var body: some View {
        let c = MolibooFamilyStyle.color(family)
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [c.opacity(0.28), c.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                MolibooMarketplaceArtwork(character: character, tint: c)
                    .padding(6)
                Text("✦ Series 2").font(.caption2.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.white.opacity(0.9), in: Capsule()).foregroundStyle(c)
                    .padding(8)
            }
            .frame(height: 140)
            Text("#\(character.catalogueNumber) · \((family?.label ?? character.familyId).uppercased())")
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                .padding(.top, 4)
            Text(character.name).font(.headline).lineLimit(1)
            Text(character.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Label(stateLabel, systemImage: stateSymbol).font(.caption2.weight(.semibold)).foregroundStyle(c)
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private var stateLabel: String {
        if let update = manager.updates.first(where: { $0.packageId == character.packageId }) { return "Update \(update.version)" }
        if manager.installedVersions[character.packageId] != nil { return "Installed" }
        return app.molibooOwnership.owns(characterID: character.id) ? "Owned · ready to install" : "Not owned"
    }

    private var stateSymbol: String {
        if manager.updates.contains(where: { $0.packageId == character.packageId }) { return "arrow.triangle.2.circlepath" }
        if manager.installedVersions[character.packageId] != nil { return "checkmark.circle.fill" }
        return app.molibooOwnership.owns(characterID: character.id) ? "arrow.down.circle" : "lock"
    }
}

/// Family collection (mockup 03): banner + "Meet <family>" two-column rows.
struct MolibooFamilyCollection: View {
    let family: MolibooRegistryFamily
    let characters: [MolibooRegistryCharacter]
    let open: (MolibooRegistryCharacter) -> Void

    var body: some View {
        let c = MolibooFamilyStyle.color(family)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MolibooHeroBanner(eyebrow: "\(family.label.uppercased()) · #\(family.range.first ?? 0)–\(family.range.last ?? 0)",
                                  title: family.name, subtitle: family.artDirection ?? family.palette ?? "",
                                  colors: MolibooFamilyStyle.gradient(family), kind: characters.first?.kind, action: nil)
                HStack {
                    Text("Meet \(family.name)").font(.title3.weight(.bold))
                    Spacer()
                    Text("\(characters.count) characters").font(.caption.weight(.semibold)).foregroundStyle(.pink)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(characters) { m in
                        Button { open(m) } label: {
                            HStack(spacing: 8) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(c.opacity(0.18))
                                    MolibooMarketplaceArtwork(character: m, tint: c).padding(2)
                                }
                                .frame(width: 70, height: 70)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("#\(m.catalogueNumber)").font(.caption2).foregroundStyle(.secondary)
                                    Text(m.name).font(.subheadline.weight(.bold)).lineLimit(1)
                                    Label("View", systemImage: "arrow.up.right").font(.caption2.weight(.semibold)).foregroundStyle(.pink)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(8)
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("moliboo.marketplace.collection.\(m.key)")
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle(family.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MolibooMarketplaceDetail: View {
    let character: MolibooRegistryCharacter
    let family: MolibooRegistryFamily?
    @Environment(AppEnvironment.self) private var app
    @State private var mood: MolibooStickerExpression = MolibooStickerExpression.all[0]
    @State private var copied: String?
    @State private var manager = MolibooPackageManager.shared
    @State private var operationInFlight = false
    @State private var operationMessage: String?
    private var installedVersion: String? {
        MolibooPackageManager.shared.runtime.store.index(character.packageId).active
    }

    var body: some View {
        let c = MolibooFamilyStyle.color(family)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(LinearGradient(colors: [c.opacity(0.35), c.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                    if let kind = character.kind {
                        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
                            ModulaMascotFigure(kind: kind, pose: MascotPose(t: ctx.date.timeIntervalSinceReferenceDate, mood: mood.mood, amp: 1), size: 120)
                        }
                        .frame(maxWidth: .infinity).frame(height: 240)
                    } else {
                        MolibooMarketplaceArtwork(character: character, tint: c).frame(height: 240).padding(12)
                    }
                    Text("✦ Series 2 · Signed content").font(.caption.weight(.bold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.white.opacity(0.9), in: Capsule()).foregroundStyle(c)
                        .padding(12)
                }
                .frame(height: 260)
                VStack(spacing: 4) {
                    Text("#\(character.catalogueNumber) · \((family?.name ?? character.familyId).uppercased())")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(character.name).font(.system(.largeTitle, design: .rounded).weight(.bold))
                    Text(character.title).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if !character.traits.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(Array(character.traits.prefix(4).enumerated()), id: \.offset) { _, trait in
                                Text(trait).font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Color.primary.opacity(0.06), in: Capsule())
                            }
                        }
                        .padding(.top, 6)
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Meet \(character.name)").font(.title3.weight(.bold))
                    Text(character.personality.description).font(.body)
                    Text(character.personality.disclaimer).font(.caption).foregroundStyle(.secondary)
                }
                if let kind = character.kind {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Expressions").font(.title3.weight(.bold))
                            Spacer()
                            Text("Tap to preview").font(.caption.weight(.semibold)).foregroundStyle(.pink)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(MolibooStickerExpression.all) { e in
                                    Button { mood = e } label: {
                                        VStack(spacing: 2) {
                                            ModulaMascotFigure(kind: kind, pose: e.pose, size: 26).frame(width: 56, height: 50)
                                            Text(e.label).font(.caption2)
                                        }
                                        .padding(6)
                                        .background((mood == e ? c.opacity(0.25) : Color.primary.opacity(0.05)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Stickers").font(.title3.weight(.bold))
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(MolibooStickerExpression.all.prefix(6)) { e in
                                    Button {
                                        copied = MolibooStickerExpression.copy(kind: kind, e) ? "\(e.label) sticker copied" : "Couldn't make that sticker"
                                    } label: { MolibooStickerArt(kind: kind, expression: e, size: 84) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("\(character.name) \(e.label) sticker")
                                }
                            }
                        }
                        if let copied { Text(copied).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                    }
                }
                if let family {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Family").font(.title3.weight(.bold))
                        Text(family.name).font(.body.weight(.semibold))
                        if let direction = family.artDirection { Text(direction).font(.body) }
                        if let palette = family.palette { Text(palette).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Artwork").font(.title3.weight(.bold))
                    if character.kind != nil {
                        Text("Drawn live by the Moliboo rig, like #001–115: wardrobe, expressions and motion work the same.")
                    } else if let installedVersion {
                        Text("Installed pack \(installedVersion). The portrait is the full image from that pack.")
                    } else {
                        Text("Not installed. The figure above is a placeholder until the on-demand pack is installed.")
                    }
                    Text(character.wearable ? "Wardrobe items fit through the shared rig anchors. Equipped state follows your Modula account." : "This character does not support wardrobe items.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    Task { await installOrEquip() }
                } label: {
                    HStack(spacing: 8) {
                        if operationInFlight { ProgressView().controlSize(.small) }
                        Text(actionTitle).font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .modulaGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: app.auth.isSignedIn)
                .disabled(operationInFlight || !app.auth.isSignedIn || isEquipped)
                .accessibilityIdentifier("moliboo.marketplace.purchase")
                .accessibilityHint(actionHint)
                Text(operationMessage ?? app.molibooOwnership.error ?? actionHint)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .navigationTitle(character.name)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("moliboo.marketplace.detail.\(character.key)")
        .task {
            await manager.refreshCatalog()
            if app.auth.isSignedIn { await app.molibooOwnership.refresh() }
        }
    }

    private var isOwned: Bool { app.molibooOwnership.owns(characterID: character.id) }
    private var isEquipped: Bool {
        app.molibooOwnership.outfit.items.contains { $0.slot == "character" && $0.character?.characterId == character.id && !$0.revoked }
    }
    private var latest: MolibooPackageDescriptor? { manager.latestByPackage[character.packageId] }

    private var actionTitle: String {
        if !app.auth.isSignedIn { return "Sign in to install" }
        if isEquipped { return "Equipped" }
        if !isOwned { return "Check ownership" }
        if let latest, installedVersion.map({ MolibooPackageValidator.compareSemVer(latest.version, $0) > 0 }) == true {
            return "Update signed pack"
        }
        if installedVersion == nil { return MolibooMarketplaceFacts.purchaseTitle }
        return "Equip \(character.name)"
    }

    private var actionHint: String {
        if !app.auth.isSignedIn { return "Sign in with the account that owns this Moliboo." }
        if !isOwned { return "Ownership must be confirmed by GreenField before installation or equipping." }
        return MolibooMarketplaceFacts.purchaseReason
    }

    private func installOrEquip() async {
        guard app.auth.isSignedIn, !operationInFlight else { return }
        operationInFlight = true
        defer { operationInFlight = false }
        await app.molibooOwnership.refresh()
        guard app.molibooOwnership.canActivate(characterID: character.id) else {
            operationMessage = app.molibooOwnership.error ?? "This account does not own \(character.name)."
            return
        }
        if latest == nil { await manager.refreshCatalog() }
        guard let descriptor = manager.latestByPackage[character.packageId] else {
            operationMessage = manager.lastError ?? "No approved signed pack is available."
            return
        }
        if installedVersion.map({ MolibooPackageValidator.compareSemVer(descriptor.version, $0) > 0 }) ?? true {
            guard await manager.install(descriptor) else {
                operationMessage = manager.lastError ?? "The signed pack could not be installed."
                return
            }
        }
        if await app.molibooOwnership.equip(character: character) {
            operationMessage = "\(character.name) is installed and equipped on your account."
        } else {
            operationMessage = app.molibooOwnership.error
        }
    }
}

struct MolibooMarketplaceArtwork: View {
    let character: MolibooRegistryCharacter
    var tint: Color?
    private var store: MolibooPackageStore { MolibooPackageManager.shared.runtime.store }

    var body: some View {
        // Native first: Series 2 is drawn by the same rig as #001–115. The package portrait is only a fallback.
        if let kind = character.kind {
            GeometryReader { geo in
                let s = max(1, min(geo.size.width / 2.0, geo.size.height / 1.9))
                ModulaMascotFigure(kind: kind, pose: .still(), size: s)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .accessibilityLabel("\(character.name)")
        // Fit the whole portrait. A fill would crop it, and a cropped Moliboo is not shipped.
        } else if let data = store.activeMedia(packageId: character.packageId, path: "portrait.png"),
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
