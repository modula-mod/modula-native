import SwiftUI
import UIKit

/// MOL-03 C: pre-rendered portraits (Tools/moliboo/engine/render_portraits.py, transparent 512², rendered from the
/// shipped USDZs). Used wherever loading RealityKit would be too heavy: collection picker, Settings, composer, Home.
@MainActor
enum MolibooPortrait {
    private static var cache: [String: UIImage] = [:]
    static func image(for id: String) -> UIImage? {
        guard MolibooFeatureFlags.native3DEnabled else { return render2D(id) }
        guard let d = MolibooRegistry.descriptor(for: id) else { return nil }   // only real 3D characters have portraits
        if let i = cache[d.id] { return i }
        guard let url = Bundle.main.url(forResource: "Portrait_\(d.displayName)", withExtension: "png"),
              let i = UIImage(contentsOfFile: url.path) else { return nil }
        cache[d.id] = i
        return i
    }
    /// 2D-only Moliboos: every portrait surface (Home, cards, Welcome, collection, Settings, composer) gets the 2D
    /// renderer's figure in the current outfit instead of the USDZ-rendered PNG. Cached per character + outfit.
    private static var cache2D: [String: UIImage] = [:]
    private static func render2D(_ id: String) -> UIImage? {
        guard let kind = ModulaMascotKind(rawValue: id) else { return nil }
        let outfit = MascotWardrobeStore.shared.outfit
        let key = id + "|" + outfit.items.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            + "|" + outfit.dyes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        if let i = cache2D[key] { return i }
        let s: CGFloat = 180
        let r = ImageRenderer(content: ModulaMascotFigure(kind: kind, pose: .still(), size: s, outfit: outfit)
            .frame(width: s * 1.45, height: s * 1.45))
        r.scale = 2
        guard let i = r.uiImage else { return nil }
        if cache2D.count > 64 { cache2D.removeAll() }
        cache2D[key] = i
        return i
    }
    /// Lightweight 3D presentation (portrait, no RealityKit) is used only with the dev flag on.
    static func usesPortrait(_ id: String) -> Bool { MolibooFeatureFlags.native3DEnabled && image(for: id) != nil }
}

/// Lightweight companion presentation for 3D-capable Moliboos: the portrait with a gentle breathing bob
/// (static under Reduced Motion or when the host says not animated).
struct MolibooPortraitCompanion: View {
    let characterID: String
    var size: CGFloat
    var animated = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false

    var body: some View {
        if let img = MolibooPortrait.image(for: characterID) {
            Image(uiImage: img)
                .resizable().scaledToFit()
                .frame(width: size * 1.7, height: size * 1.7)
                .scaleEffect(x: 1, y: up ? 1.025 : 1, anchor: .bottom)
                .offset(y: up ? -size * 0.03 : 0)
                .shadow(color: .black.opacity(0.12), radius: 4, y: 3)
                .onAppear {
                    guard animated, !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { up = true }
                }
                .accessibilityIdentifier("moliboo.companion.portrait.\(characterID)")
                .accessibilityLabel(MolibooRegistry.descriptor(for: characterID)?.displayName ?? "Moliboo")
        }
    }
}

/// MOL-03R Redesigned Collection over the 25 Originals: responsive 2-column grid on iPhones,
/// pre-rendered 3D portraits (never RealityKit per card), verified search & filter chips,
/// monospaced catalogue badges, concise personality lines, and full bottom safe-area clearance.
struct MolibooCollectionView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case threeD = "In Studio"
        case owned = "Unlocked"
        case comingLater = "Coming Later"
        var id: String { rawValue }
    }

    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var studioFor: String?
    @State private var searchText = ""
    @State private var filter: Filter = .all
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
    private let teal = Color(red: 0.21, green: 0.61, blue: 0.67)

    private var filteredOriginals: [(index: Int, id: String)] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return MolibooCosmetics.originals.enumerated().compactMap { idx, id in
            let has3D = MolibooRegistry.has3D(id)
            let kind = ModulaMascotKind(rawValue: id)
            let unlocked = kind.map(MascotEntitlements.canUse) ?? false
            switch filter {
            case .all: break
            case .threeD: guard has3D else { return nil }
            case .owned: guard unlocked else { return nil }
            case .comingLater: guard !has3D else { return nil }
            }
            if !q.isEmpty {
                let name = (MolibooRegistry.manifest?.character(id: id)?.displayName ?? id).lowercased()
                let bio = (kind?.personality ?? "").lowercased()
                let num = String(format: "%03d", idx + 1)
                guard name.contains(q) || bio.contains(q) || num.contains(q) else { return nil }
            }
            return (idx + 1, id)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerCard
                filterBar
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(filteredOriginals, id: \.id) { entry in
                        tile(id: entry.id, number: entry.index)
                    }
                }
            }
            .padding(16)
        }
        .contentMargins(.bottom, 96, for: .scrollContent)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Collection")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search Originals by name or #")
        .navigationDestination(item: $studioFor) { id in MolibooLivingStudioView(characterID: id) }
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("The Originals")
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                Text("\(MolibooRegistry.available3D.count) of \(MolibooCosmetics.originals.count) Originals are ready to play")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("collection.summary")
            }
            Spacer()
            Text("\(MolibooRegistry.available3D.count)/\(MolibooCosmetics.originals.count)")
                .font(.subheadline.weight(.heavy).monospaced())
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(teal.gradient, in: Capsule())
        }
        .padding(14)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false, specular: true)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases) { f in
                    let on = filter == f
                    Button {
                        withAnimation(reduceMotion ? nil : .snappy) { filter = f }
                    } label: {
                        Text(f.rawValue)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(on ? .white : .primary)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .modulaGlass(in: Capsule(), interactive: true, tint: on ? teal : nil, prominent: on)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("collection.filter.\(f.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder private func tile(id: String, number: Int) -> some View {
        let has3D = MolibooRegistry.has3D(id)
        let kind = ModulaMascotKind(rawValue: id)
        let selected = kindRaw == id
        let unlocked = kind.map(MascotEntitlements.canUse) ?? false
        let name = MolibooRegistry.manifest?.character(id: id)?.displayName ?? id.capitalized
        let bio = kind?.shortPersonality ?? "Coming in a future update."
        let pal = kind?.palette

        Button {
            if kind != nil && unlocked { kindRaw = id }
            if has3D { studioFor = id }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(has3D
                              ? AnyShapeStyle(LinearGradient(colors: [(pal?.light ?? teal).opacity(0.9), (pal?.mid ?? teal).opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
                              : AnyShapeStyle(Color.secondary.opacity(0.12)))
                        .overlay {
                            if selected {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(.white.opacity(0.16))
                                    .molibooHoloFoil(0.5, animated: !reduceMotion)
                            }
                        }

                    Group {
                        if has3D, let img = MolibooPortrait.image(for: id) {
                            Image(uiImage: img)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .padding(10)
                                .molibooPortraitEdge()
                                .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
                        } else if let kind {
                            ModulaMascotFigure(kind: kind, pose: .still(), size: 38).opacity(0.85)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.title.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    HStack(spacing: 4) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(teal, in: Circle())
                        }
                        statusBadge(has3D: has3D, kind: kind, unlocked: unlocked)
                    }
                    .padding(8)
                }
                .frame(height: 128)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "#%03d", number))
                            .font(.caption2.weight(.bold).monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Text(bio)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(minHeight: 30, alignment: .topLeading)
                }
                .padding(.horizontal, 4)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(selected ? teal : Color.primary.opacity(0.06), lineWidth: selected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(MolibooSpringPressStyle())
        .accessibilityIdentifier("collection.\(id)")
        .accessibilityLabel("\(name), number \(number), \(has3D ? "in Studio" : "coming later")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private func statusBadge(has3D: Bool, kind: ModulaMascotKind?, unlocked: Bool) -> some View {
        if has3D {
            Text("Studio")
                .font(.caption2.weight(.heavy))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(teal, in: Capsule())
                .foregroundStyle(.white)
        } else if let kind, kind.isPremium && !unlocked {
            Label("Locked", systemImage: "lock.fill")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(Color.orange.opacity(0.2), in: Capsule())
                .foregroundStyle(.orange)
        } else {
            Text("Coming later")
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(Color.secondary.opacity(0.2), in: Capsule())
                .foregroundStyle(.secondary)
        }
    }
}
