import SwiftUI
import UIKit

// MARK: - Wardrobe 2.0 (Living Studio)

enum MolibooWardrobeOwnership: String, CaseIterable, Identifiable, Sendable {
    case all, owned
    var id: String { rawValue }
    var title: String { self == .all ? "All" : "Owned" }
}

/// Search + filters over the existing catalog. IDs, slots and unlocks come straight from `MascotWardrobeCatalog`.
struct MolibooWardrobeQuery: Equatable, Sendable {
    var text = ""
    var slot: MascotWardrobeSlot?
    var ownership: MolibooWardrobeOwnership = .all
    var only3D = false

    func filter(_ items: [MascotWardrobeItem], owns: (MascotWardrobeItem) -> Bool, supports3D: (String) -> Bool) -> [MascotWardrobeItem] {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matched = items.filter { item in
            if let slot, item.slot != slot { return false }
            if ownership == .owned, !owns(item) { return false }
            if only3D, !supports3D(item.id) { return false }
            if q.isEmpty { return true }
            return item.name.lowercased().contains(q) || item.blurb.lowercased().contains(q)
                || item.id.lowercased().contains(q) || item.slot.title.lowercased().contains(q)
        }
        // Keep the hero first-party Signature Cap featured at the top of the grid when matched.
        return matched.sorted { a, b in
            if a.id == MolibooCosmetics.signatureCapID { return true }
            if b.id == MolibooCosmetics.signatureCapID { return false }
            return false
        }
    }
}

/// Try-on session over the shared store: a staged outfit you can preview (the 3D stage syncs to it without reloading
/// the character), then apply (ownership-checked, undoable through the store), revert, undo, or save as an outfit.
@MainActor @Observable
final class MolibooWardrobeSession {
    let store: MascotWardrobeStore
    private(set) var preview: MascotOutfit
    private(set) var lastTriedID: String?
    /// Fit-table items (generic per-item assets); nil until a character is loaded.
    var rig: MolibooWardrobeRig?

    init(store: MascotWardrobeStore = .shared) {
        self.store = store
        preview = store.outfit
    }

    var isPreviewing: Bool { preview != store.outfit }
    /// Staged items the user can't wear yet (not owned or out of season): preview only.
    var blocked: [MascotWardrobeItem] {
        preview.items.values.compactMap(MascotWardrobeCatalog.item(id:)).filter { !store.canEquip($0) }
    }
    var canApply: Bool { isPreviewing && blocked.isEmpty }
    var canUndo: Bool { store.canUndo }
    var previewIDs: [String] { preview.equippedIDs }

    /// Try on / take off in the preview. Same slot replaces (so the Signature Cap and the Party cone swap, never merge).
    func tryOn(_ item: MascotWardrobeItem) {
        var next = preview
        if next.contains(item) { next.unequip(item.slot) } else { next.equip(item) }
        preview = next
        lastTriedID = item.id
    }

    func apply() {
        guard canApply else { return }
        store.apply(preview)
        resync()
    }
    func revert() { resync() }
    func undo() { store.undo(); resync() }
    /// Saves what you see: applies a pending (allowed) preview first, then stores the outfit as a preset.
    func save(named name: String) {
        if canApply { apply() }
        guard !isPreviewing else { return }
        store.savePreset(named: name)
    }
    func load(_ preset: MascotOutfitPreset) { store.applyPreset(preset); resync() }
    func delete(_ preset: MascotOutfitPreset) { store.deletePreset(preset) }
    /// Re-read the store (after the cap quick toggle or an external change).
    func resync() { preview = store.outfit; lastTriedID = nil }
}

/// Shipped per-item renders (`MolibooWardrobe/Thumbs/WardrobeThumb_<id>.png`, rendered from the item USDZs), cached.
@MainActor
enum MolibooWardrobeThumbs {
    private static let cache = NSCache<NSString, UIImage>()
    static func image(_ id: String) -> UIImage? {
        if let i = cache.object(forKey: id as NSString) { return i }
        guard let url = Bundle.main.url(forResource: "WardrobeThumb_\(id)", withExtension: "png", subdirectory: "MolibooWardrobe/Thumbs"),
              let i = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(i, forKey: id as NSString)
        return i
    }
}

struct MolibooWardrobeSheet: View {
    let controller: MolibooSceneController
    @Bindable var session: MolibooWardrobeSession
    @State private var query = MolibooWardrobeQuery()
    @State private var saving = false
    @State private var outfitName = ""
    private let columns = [GridItem(.adaptive(minimum: 102), spacing: 10)]

    private var results: [MascotWardrobeItem] {
        query.filter(MascotWardrobeCatalog.all, owns: session.store.owns, supports3D: supports3D)
    }

    private func supports3D(_ id: String) -> Bool { controller.isSupported(wardrobeItemID: id) || session.rig?.supports(id) == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Wardrobe").font(.headline)
                Spacer()
                Text(results.count == 1 ? "1 item" : "\(results.count) items")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("wardrobe.count")
            }
            TextField("Search hats, tops, colours…", text: $query.text)
                .textFieldStyle(.roundedBorder).autocorrectionDisabled().textInputAutocapitalization(.never).submitLabel(.search)
                .accessibilityIdentifier("wardrobe.search")
                .overlay(alignment: .trailing) {
                    if !query.text.isEmpty {
                        Button { query.text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .padding(.trailing, 6).accessibilityIdentifier("wardrobe.search.clear").accessibilityLabel("Clear search")
                    }
                }
            filters
            actionBar
            if !session.store.presets.isEmpty { presetsRow }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(results, id: \.id) { item in tile(item) }
                }
                .padding(.bottom, 36)
            }
            .contentMargins(.bottom, 28, for: .scrollContent)
            .scrollDismissesKeyboard(.immediately)
        }
        .padding(.horizontal, 20).padding(.top, 12)
        .onChange(of: session.previewIDs) { _, ids in
            Task {
                await controller.sync(outfitItemIDs: ids)
                await session.rig?.sync(ids.filter { !controller.isSupported(wardrobeItemID: $0) })
            }
        }
        .alert("Save outfit", isPresented: $saving) {
            TextField("Name", text: $outfitName).accessibilityIdentifier("wardrobe.saveName")
            Button("Save") { session.save(named: outfitName); outfitName = "" }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Picker("Ownership", selection: $query.ownership) {
                    ForEach(MolibooWardrobeOwnership.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 130)
                .accessibilityIdentifier("wardrobe.ownership")
                chip("3D", on: query.only3D, id: "wardrobe.filter.3d") { query.only3D.toggle() }
                chip("All slots", on: query.slot == nil, id: "wardrobe.slot.all") { query.slot = nil }
                ForEach(MascotWardrobeSlot.allCases) { s in
                    chip(s.title, on: query.slot == s, id: "wardrobe.slot.\(s.rawValue)") { query.slot = query.slot == s ? nil : s }
                }
            }
        }
    }

    private func chip(_ title: String, on: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption.weight(.semibold)).lineLimit(1).padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(on ? .white : .primary)
                .modulaGlass(in: Capsule(), interactive: true, tint: on ? Color.accentColor : nil, prominent: on)
        }
        .buttonStyle(.plain).accessibilityIdentifier(id).accessibilityAddTraits(on ? .isSelected : [])
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button("Apply") { session.apply() }.buttonStyle(.borderedProminent).disabled(!session.canApply)
                .accessibilityIdentifier("wardrobe.apply")
            Button("Revert") { session.revert() }.buttonStyle(.bordered).disabled(!session.isPreviewing)
                .accessibilityIdentifier("wardrobe.revert")
            Button { session.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .buttonStyle(.bordered).disabled(!session.canUndo || session.isPreviewing)
                .accessibilityIdentifier("wardrobe.undo")
            Spacer()
            Button { saving = true } label: { Label("Save", systemImage: "square.and.arrow.down") }
                .buttonStyle(.bordered).disabled(session.isPreviewing && !session.canApply)
                .accessibilityIdentifier("wardrobe.save")
        }
        .font(.subheadline)
        .overlay(alignment: .bottomLeading) {
            if !session.blocked.isEmpty {
                Text("Preview only: \(session.blocked.map(\.name).joined(separator: ", ")) isn't yours yet.")
                    .font(.caption2).foregroundStyle(.orange).offset(y: 16)
                    .accessibilityIdentifier("wardrobe.blocked")
            }
        }
        .padding(.bottom, session.blocked.isEmpty ? 0 : 14)
    }

    private var presetsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(session.store.presets, id: \.id) { p in
                    Button { session.load(p) } label: {
                        Label(p.name, systemImage: "hanger").font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .modulaGlass(in: Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { Button("Delete", role: .destructive) { session.delete(p) } }
                    .accessibilityIdentifier("wardrobe.preset.\(p.name)")
                }
            }
        }
    }

    private func tile(_ item: MascotWardrobeItem) -> some View {
        let on = session.preview.contains(item)
        let owned = session.store.owns(item)
        let in3D = supports3D(item.id)
        return Button { session.tryOn(item) } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [item.tint.opacity(0.35), item.tint.opacity(0.12)], startPoint: .top, endPoint: .bottom))
                        .overlay {
                            // Real per-item render (shipped thumbnails); the slot glyph only if an item has none.
                            if let img = MolibooWardrobeThumbs.image(item.id) {
                                Image(uiImage: img).resizable().interpolation(.high).scaledToFit().padding(6)
                                    .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                            } else {
                                Image(systemName: item.slot.symbol).font(.title3).foregroundStyle(item.tint)
                            }
                        }
                    HStack(spacing: 2) {
                        if in3D { Text("3D").font(.system(size: 9, weight: .bold)).padding(3).background(Color.accentColor, in: Capsule()).foregroundStyle(.white) }
                        if !owned { Image(systemName: "lock.fill").font(.system(size: 9)).padding(3) }
                    }
                    .padding(4)
                }
                .frame(height: 64)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(on ? Color(red: 0.21, green: 0.61, blue: 0.67) : .clear, lineWidth: 2))
                Text(item.name).font(.caption2.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.85)
                    .frame(minHeight: 26, alignment: .top)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("wardrobe.item.\(item.id)")
        .accessibilityLabel("\(item.name), \(item.slot.title)\(in3D ? ", 3D" : "")\(owned ? "" : ", locked")\(on ? ", trying on" : "")")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Photo capture

@MainActor
enum MolibooPhotoCapture {
    /// Snapshot of the key window (the Living Studio with chrome hidden), including the RealityKit layer.
    static func captureKeyWindow() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow) else { return nil }
        let r = UIGraphicsImageRenderer(bounds: window.bounds)
        return r.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
    }

    /// True when the middle of the frame differs from the same row's edge: the backdrop gradient is uniform across x,
    /// so a difference means the character was actually captured (not a blank Metal layer).
    static func showsSubject(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        let w = 32, h = 32
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        func at(_ x: Int, _ y: Int) -> (Int, Int, Int) { let i = (y * w + x) * 4; return (Int(px[i]), Int(px[i + 1]), Int(px[i + 2])) }
        var maxDiff = 0
        for y in (h / 3)...(2 * h / 3) {
            let edge = at(1, y)
            for x in (w / 3)...(2 * w / 3) {
                let c = at(x, y)
                maxDiff = max(maxDiff, abs(c.0 - edge.0) + abs(c.1 - edge.1) + abs(c.2 - edge.2))
            }
        }
        return maxDiff > 60
    }
}

struct MolibooCapturedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct MolibooPhotoPreview: View {
    let photo: MolibooCapturedPhoto
    let characterName: String
    var onDone: () -> Void
    private var picture: Image { Image(uiImage: photo.image) }
    private var shareTitle: String { "\(characterName) in the Studio" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(uiImage: photo.image).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(radius: 8).padding(.horizontal, 24)
                    .accessibilityIdentifier("studio.photo.preview")
                ShareLink(item: picture, preview: SwiftUI.SharePreview(shareTitle, image: picture)) {
                    Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).padding(.horizontal, 24)
                .accessibilityIdentifier("studio.photo.share")
            }
            .navigationTitle("Photo").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone).accessibilityIdentifier("studio.photo.previewDone") } }
        }
    }
}
