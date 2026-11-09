import SwiftUI
import UIKit

// MARK: - Card collection (all 215)

struct MolibooCardCollectionView: View {
    var registry: MolibooCharacterRegistry? = MolibooRegistryStore.bundled
    var outfit: MascotOutfit = MascotWardrobeStore.shared.outfit

    @State private var familyFilter: String? = nil
    @State private var inspecting: MolibooGalleryCard?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cards: [MolibooGalleryCard] { MolibooCardGallery.all(registry: registry) }
    private var families: [MolibooRegistryFamily] {
        (registry?.families ?? []).sorted { ($0.range.first ?? 0) < ($1.range.first ?? 0) }
    }
    private var visible: [MolibooGalleryCard] {
        cards.filter { familyFilter == nil || $0.familyId == familyFilter }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 148, maximum: 200), spacing: 14, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                familyChips
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(visible) { card in
                        Button { inspecting = card } label: {
                            MolibooTradingCardV2(card: card, width: 156, outfit: outfit, interactive: false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("cards.collection.\(card.catalogueNumber)")
                    }
                }
                Text("\(visible.count) of \(cards.count) Moliboos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 28)
                    .accessibilityIdentifier("cards.collection.count")
            }
            .padding(.horizontal, 18)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .sheet(item: $inspecting) { card in
            MolibooGalleryInspectView(card: card, outfit: outfit) { inspecting = nil }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Card Collection")
                .font(.title2.weight(.bold))
            Text("Every Moliboo has a card — #001 to #215. This is the catalogue, not a claim of ownership.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    private var familyChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", on: familyFilter == nil) { familyFilter = nil }
                ForEach(families) { family in
                    chip(family.name, on: familyFilter == family.id) {
                        familyFilter = familyFilter == family.id ? nil : family.id
                    }
                }
            }
        }
        .modulaHorizontalEdgeFade()
        .accessibilityIdentifier("cards.collection.families")
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(on ? .white : .primary)
                .modulaGlass(in: Capsule(), interactive: true, tint: on ? Color.accentColor : nil, prominent: on)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Cards home (collection + founding packs)

enum MolibooCardsHomeTab: String, CaseIterable, Identifiable {
    case collection, founding
    var id: String { rawValue }
    var title: String { self == .collection ? "Collection" : "Founding packs" }
}

struct MolibooCardsHomeView: View {
    @State private var tab: MolibooCardsHomeTab = .collection

    var body: some View {
        VStack(spacing: 0) {
            Picker("Cards", selection: $tab) {
                ForEach(MolibooCardsHomeTab.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .accessibilityIdentifier("cards.home.tab")

            switch tab {
            case .collection:
                MolibooCardCollectionView()
            case .founding:
                MolibooCardBinderView()
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Cards")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("cards.home")
    }
}

// MARK: - QA contact sheets (ImageRenderer, used by tests or a debug export)

enum MolibooCardQA {
    @MainActor
    static func renderCollectionSheet(registry: MolibooCharacterRegistry? = MolibooRegistryStore.bundled, outfit: MascotOutfit = .empty) -> UIImage? {
        let cards = MolibooCardGallery.all(registry: registry)
        let columns = 10
        let cardW: CGFloat = 156
        let cardH = cardW * MolibooTradingCardV2.base.height / MolibooTradingCardV2.base.width
        let gap: CGFloat = 10
        let rows = Int(ceil(Double(cards.count) / Double(columns)))
        let width = CGFloat(columns) * cardW + CGFloat(columns + 1) * gap
        let height = CGFloat(rows) * cardH + CGFloat(rows + 1) * gap + 48
        let view = VStack(alignment: .leading, spacing: 12) {
            Text("Moliboo Trading Cards  ·  #001–#215")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .padding(.leading, gap)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cardW), spacing: gap), count: columns), spacing: gap) {
                ForEach(cards) { card in
                    MolibooTradingCardV2(card: card, width: cardW, outfit: outfit, interactive: false)
                }
            }
        }
        .padding(gap)
        .frame(width: width, height: height)
        .background(Color(red: 0.94, green: 0.93, blue: 0.90))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }

    @MainActor
    static func writeCollectionSheet(to url: URL, registry: MolibooCharacterRegistry? = MolibooRegistryStore.bundled, outfit: MascotOutfit = .empty) throws {
        guard let image = renderCollectionSheet(registry: registry, outfit: outfit), let data = image.pngData() else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

enum MolibooCostumeQA {
    @MainActor
    static func renderSheet() -> UIImage? {
        let costumes = MascotWardrobeCatalog.items(in: .costume)
        let subjects: [(String, ModulaMascotKind)] = [
            ("Original  ·  Pip", .pip),
            ("Series 2  ·  Brinlo", ModulaMascotKind(rawValue: "brinlo") ?? .pip),
            ("Legend  ·  Kringle (blocked)", .kringle),
        ]
        let size: CGFloat = 72
        let view = VStack(alignment: .leading, spacing: 16) {
            Text("Moliboo Costumes")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            ForEach(subjects, id: \.0) { label, kind in
                VStack(alignment: .leading, spacing: 8) {
                    Text(label).font(.system(size: 14, weight: .semibold, design: .rounded))
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(110), spacing: 8), count: 5), spacing: 10) {
                        ForEach(costumes, id: \.id) { item in
                            VStack(spacing: 4) {
                                ModulaMascotFigure(kind: kind, pose: .still(.happy), size: size, outfit: kind.supportsWardrobe ? .solo(item) : .empty)
                                    .frame(width: 110, height: 100)
                                Text(item.name)
                                    .font(.system(size: 9, weight: .medium))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 640)
        .background(Color(red: 0.95, green: 0.94, blue: 0.91))

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }

    @MainActor
    static func writeSheet(to url: URL) throws {
        guard let image = renderSheet(), let data = image.pngData() else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
