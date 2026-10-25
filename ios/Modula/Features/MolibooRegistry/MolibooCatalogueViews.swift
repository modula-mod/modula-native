import SwiftUI

// MOL-03D: registry-driven collection browser and character detail for all 115 Moliboos.
// Thumbnails are static (`.still`) figures in a lazy grid; only the detail screen mounts an animated renderer,
// and `MolibooActiveRendererBudget` keeps at most one animated figure live at a time.

enum MolibooDownloadState: Equatable {
    case builtIn
    case installed(String)
    case updateAvailable(String)

    var label: String {
        switch self {
        case .builtIn: "Built in"
        case .installed(let v): "Artwork \(v)"
        case .updateAvailable(let v): "Update \(v)"
        }
    }

    var symbol: String {
        switch self {
        case .builtIn: "checkmark.seal"
        case .installed: "arrow.down.circle.fill"
        case .updateAvailable: "arrow.triangle.2.circlepath.circle"
        }
    }
}

@MainActor
enum MolibooCatalogueQuery {
    /// Pure filter used by the browser and tests: family (nil = all) and a case-insensitive search over
    /// name, number, title, traits and family name.
    static func filter(_ characters: [MolibooRegistryCharacter], family: String?, search: String, families: [MolibooRegistryFamily]) -> [MolibooRegistryCharacter] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let names = Dictionary(uniqueKeysWithValues: families.map { ($0.id, $0.name.lowercased()) })
        return characters.filter { c in
            if let family, c.familyId != family { return false }
            guard !q.isEmpty else { return true }
            if c.name.lowercased().contains(q) || c.title.lowercased().contains(q) || c.catalogueNumber.contains(q) || String(c.number) == q { return true }
            if c.traits.contains(where: { $0.lowercased().contains(q) }) { return true }
            return names[c.familyId]?.contains(q) ?? false
        }
    }

    static func downloadState(_ c: MolibooRegistryCharacter, manager: MolibooPackageManager) -> MolibooDownloadState {
        if let update = manager.updates.first(where: { $0.packageId == c.packageId }) { return .updateAvailable(update.version) }
        if let v = manager.installedVersions[c.packageId] { return .installed(v) }
        return .builtIn
    }
}

struct MolibooCollectionBrowser: View {
    var onSelect: (ModulaMascotKind) -> Void = { _ in }
    @State private var family: String?
    @State private var search = ""
    @State private var manager = MolibooPackageManager.shared
    private let registry = MolibooRegistryStore.bundled

    var body: some View {
        let families = registry?.families ?? []
        let shown = MolibooCatalogueQuery.filter(registry?.characters ?? [], family: family, search: search, families: families)
        let _ = MolibooPackageRevision.shared.observedValue
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    ModulaGlassGroup(spacing: 8) {
                        HStack(spacing: 8) {
                            chip("All", selected: family == nil) { family = nil }
                            ForEach(families) { f in chip(f.label, selected: family == f.id) { family = f.id } }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                Text("\(shown.count) of \(registry?.characters.count ?? 0)")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("moliboo.collection.count")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                    ForEach(shown) { c in
                        if let kind = c.kind {
                            Button { onSelect(kind) } label: { tile(c, kind: kind) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("moliboo.collection.\(c.key)")
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 12)
        }
        .searchable(text: $search, prompt: "Search Moliboos")
        .navigationTitle("Moliboos")
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

    private func tile(_ c: MolibooRegistryCharacter, kind: ModulaMascotKind) -> some View {
        let state = MolibooCatalogueQuery.downloadState(c, manager: manager)
        return VStack(spacing: 4) {
            ModulaMascotFigure(kind: kind, pose: .still(), size: 34)
                .frame(width: 72, height: 66)
            Text(c.name).font(.caption.weight(.bold)).lineLimit(1)
            HStack(spacing: 3) {
                Text("#\(c.catalogueNumber)").font(.caption2.monospaced())
                Image(systemName: state.symbol).font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(c.name), number \(c.number), \(state.label)")
    }
}

struct MolibooCharacterDetailView: View {
    let kind: ModulaMascotKind
    var outfit: MascotOutfit = .empty
    @State private var lastReaction: String?
    @State private var manager = MolibooPackageManager.shared

    var body: some View {
        let _ = MolibooPackageRevision.shared.observedValue
        if let c = kind.registryEntry {
            ScrollView {
                VStack(spacing: 18) {
                    MolibooAnimatedFigure(kind: kind, size: 120, outfit: kind.supportsWardrobe ? outfit : .empty) { lastReaction = $0 }
                        .frame(height: 240)
                    VStack(spacing: 4) {
                        Text(c.name).font(.system(.title2, design: .rounded).weight(.heavy))
                        Text("#\(c.catalogueNumber) · \(familyName(c)) · \(c.title)")
                            .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    section("Personality") {
                        Text(c.personality.description).font(.body)
                        meter("Energy", c.personality.energy)
                        meter("Curiosity", c.personality.curiosity)
                        meter("Sociability", c.personality.sociability)
                    }
                    if let sig = c.signature {
                        section("Signature move") {
                            Text(sig.line ?? sig.id ?? "").font(.body.italic())
                            if let lastReaction { Text("Last reaction: \(lastReaction)").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    section("Expressions") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(c.expressions, id: \.self) { e in
                                    VStack(spacing: 2) {
                                        ModulaMascotFigure(kind: kind, pose: .still(e.mood), size: 26).frame(width: 56, height: 52)
                                        Text(e.title).font(.caption2)
                                    }
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(e.title)
                                }
                            }
                        }
                    }
                    section("Wardrobe") {
                        Text(c.wearable ? "Wears Moliboo accessories, fitted for its shape." : "A Legend wears its own look, so accessories are not shown.")
                            .font(.body)
                    }
                    section("Artwork") {
                        let state = MolibooCatalogueQuery.downloadState(c, manager: manager)
                        Label(state.label, systemImage: state.symbol).font(.body)
                        Text("Works offline once installed. Built-in art is always kept.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            .navigationTitle(c.name)
            .accessibilityIdentifier("moliboo.detail.\(c.key)")
        } else {
            ContentUnavailableView("Moliboo unavailable", systemImage: "questionmark.circle")
        }
    }

    private func familyName(_ c: MolibooRegistryCharacter) -> String {
        MolibooRegistryStore.bundled?.families.first { $0.id == c.familyId }?.name ?? c.familyId
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

    private func meter(_ title: String, _ value: Double) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            ProgressView(value: min(max(value, 0), 1)).frame(width: 120)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
    }
}
