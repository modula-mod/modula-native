import SwiftUI
import UIKit

/// MOL-03 C: pre-rendered portraits (Tools/moliboo/engine/render_portraits.py, transparent 512², rendered from the
/// shipped USDZs). Used wherever loading RealityKit would be too heavy: collection picker, Settings, composer, Home.
@MainActor
enum MolibooPortrait {
    private static var cache: [String: UIImage] = [:]
    static func image(for id: String) -> UIImage? {
        guard MolibooFeatureFlags.native3DEnabled else { return render2D(id, pointSize: 180, scale: 2) }
        guard let d = MolibooRegistry.descriptor(for: id) else { return render2D(id, pointSize: 180, scale: 2) }
        if let i = cache[d.id] { return i }
        guard let url = Bundle.main.url(forResource: "Portrait_\(d.displayName)", withExtension: "png"),
              let i = UIImage(contentsOfFile: url.path) else { return render2D(id, pointSize: 180, scale: 2) }
        cache[d.id] = i
        return i
    }

    /// Small static thumb for scrolling roster tiles. Never live SwiftUI figures.
    static func thumb(for id: String) -> UIImage? {
        render2D(id, pointSize: 64, scale: 2, cachePrefix: "thumb|")
    }

    /// 2D-only Moliboos: ImageRenderer snapshot of the figure, cached. Cap is large enough for all 100
    /// characters + a few outfit variants so scroll never thrash-clears and re-renders.
    private static var cache2D: [String: UIImage] = [:]
    private static let cache2DCap = 256

    private static func outfitKey(_ outfit: MascotOutfit) -> String {
        outfit.items.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            + "|" + outfit.dyes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    private static func render2D(_ id: String, pointSize: CGFloat, scale: CGFloat, cachePrefix: String = "") -> UIImage? {
        guard let kind = ModulaMascotKind(rawValue: id) else { return nil }
        let outfit = MascotWardrobeStore.shared.outfit
        let key = cachePrefix + id + "|" + outfitKey(outfit) + "|\(Int(pointSize))x\(Int(scale))"
        if let i = cache2D[key] { return i }
        let s = pointSize
        // Render on a canvas wider than any character (wings, tails, boards, props), then crop to
        // the real drawn bounds. The old fixed 1.45s frame cut wide Moliboos (Rumble, Skid, Asteri…)
        // off at the sides everywhere the snapshot is shown.
        let r = ImageRenderer(content: ModulaMascotFigure(kind: kind, pose: .still(), size: s, outfit: .empty)
            .frame(width: s * renderCanvas, height: s * renderCanvas))
        r.scale = scale
        guard let raw = r.cgImage, let i = fittedToDrawnBounds(raw, pointSize: s, scale: scale) else { return nil }
        if cache2D.count >= cache2DCap {
            // Drop oldest half (dict order is insertion order) instead of wiping — keeps warm thumbs.
            let drop = cache2D.keys.prefix(cache2DCap / 2)
            for k in drop { cache2D.removeValue(forKey: k) }
        }
        cache2D[key] = i
        return i
    }

    /// Side of the square render canvas, in figure sizes (figure canvas is 2.0 × 1.9).
    private static let renderCanvas: CGFloat = 2.6
    /// Minimum crop (the old fixed frame), so regular-width characters keep their usual scale.
    private static let minimumCrop: CGFloat = 1.45

    /// Crops a centred render to the smallest centred rect that contains every drawn pixel (plus a
    /// little air), never smaller than `minimumCrop`. Symmetric about the centre so every character
    /// keeps the same anchor; only wide/tall ones grow, and `scaledToFit` callers then fit them whole.
    private static func fittedToDrawnBounds(_ image: CGImage, pointSize s: CGFloat, scale: CGFloat) -> UIImage? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var alpha = [UInt8](repeating: 0, count: w * h)
        let drawn: CGRect? = alpha.withUnsafeMutableBytes { buf -> CGRect? in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return nil }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            var minX = w, maxX = -1, minY = h, maxY = -1
            let px = buf.bindMemory(to: UInt8.self)
            for y in 0..<h {
                let row = y * w
                for x in 0..<w where px[row + x] > 8 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
            guard maxX >= minX, maxY >= minY else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }
        let cx = CGFloat(w) / 2, cy = CGFloat(h) / 2
        let air = s * scale * 0.06
        let minHalf = s * scale * minimumCrop / 2
        var halfW = minHalf, halfH = minHalf
        if let d = drawn {
            halfW = max(minHalf, max(cx - d.minX, d.maxX - cx) + air)
            halfH = max(minHalf, max(cy - d.minY, d.maxY - cy) + air)
        }
        let crop = CGRect(x: cx - halfW, y: cy - halfH, width: halfW * 2, height: halfH * 2)
            .integral.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard let cropped = image.cropping(to: crop) else { return nil }
        return UIImage(cgImage: cropped, scale: scale, orientation: .up)
    }

    /// Warm tile thumbs off the critical path so Choose-your-Moliboo scroll never ImageRenderer-stalls.
    static func warmThumbs(ids: [String]) {
        for id in ids { _ = thumb(for: id) }
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
                let num = String(format: "%03d", kind?.number ?? idx + 1)
                guard name.contains(q) || bio.contains(q) || num.contains(q) else { return nil }
            }
            return (kind?.number ?? idx + 1, id)
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
        .toolbar(.hidden, for: .tabBar)
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
