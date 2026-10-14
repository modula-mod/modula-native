import SwiftUI
import UIKit

/// MOL-03 C: pre-rendered portraits (Tools/moliboo/engine/render_portraits.py, transparent 512², rendered from the
/// shipped USDZs). Used wherever loading RealityKit would be too heavy: collection picker, Settings, composer, Home.
@MainActor
enum MolibooPortrait {
    private static var cache: [String: UIImage] = [:]
    static func image(for id: String) -> UIImage? {
        guard let d = MolibooRegistry.descriptor(for: id) else { return nil }   // only real 3D characters have portraits
        if let i = cache[d.id] { return i }
        guard let url = Bundle.main.url(forResource: "Portrait_\(d.displayName)", withExtension: "png"),
              let i = UIImage(contentsOfFile: url.path) else { return nil }
        cache[d.id] = i
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

/// Collection-style picker over the 25 Originals. 3D Moliboos show their portrait and open the Living Studio;
/// the rest stay selectable as 2D companions and say "3D coming later".
struct MolibooCollectionView: View {
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    @State private var studioFor: String?
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(MolibooRegistry.available3D.count) of \(MolibooCosmetics.originals.count) Originals are alive in 3D")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("collection.summary")
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(MolibooCosmetics.originals.enumerated()), id: \.offset) { i, id in
                        tile(id: id, number: i + 1)
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Collection")
        .navigationDestination(item: $studioFor) { id in MolibooLivingStudioView(characterID: id) }
    }

    @ViewBuilder private func tile(id: String, number: Int) -> some View {
        let has3D = MolibooRegistry.has3D(id)
        let kind = ModulaMascotKind(rawValue: id)
        let selected = kindRaw == id
        Button {
            if kind != nil { kindRaw = id }
            if has3D { studioFor = id }
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(has3D ? AnyShapeStyle(LinearGradient(colors: [.accentColor.opacity(0.18), .accentColor.opacity(0.05)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(.quaternary.opacity(0.5)))
                    Group {
                        if has3D, let img = MolibooPortrait.image(for: id) {
                            Image(uiImage: img).resizable().scaledToFit().padding(8)
                        } else if let kind {
                            ModulaMascotFigure(kind: kind, pose: .still(), size: 30).opacity(0.7)
                        } else {
                            Image(systemName: "questionmark").font(.title2.weight(.bold)).foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Text(has3D ? "3D" : "Coming later")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(has3D ? Color.accentColor : Color.secondary.opacity(0.25), in: Capsule())
                        .foregroundStyle(has3D ? .white : .secondary)
                        .padding(6)
                }
                .frame(height: 100)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
                Text(String(format: "#%03d", number)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                Text(MolibooRegistry.manifest?.character(id: id)?.displayName ?? id.capitalized).font(.caption.weight(.semibold))
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("collection.\(id)")
        .accessibilityLabel("\(MolibooRegistry.manifest?.character(id: id)?.displayName ?? id), number \(number), \(has3D ? "3D" : "3D coming later")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
