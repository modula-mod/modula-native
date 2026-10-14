import SwiftUI

/// Style sheet (Living Studio). Environment + 3D cosmetics. Wardrobe 2.0 builds on this in its own PR.
struct MolibooStyleSheet: View {
    let controller: MolibooSceneController
    @Binding var environment: String
    private var wardrobe = MascotWardrobeStore.shared
    private let capID = MolibooCosmetics.signatureCapID

    init(controller: MolibooSceneController, environment: Binding<String>) {
        self.controller = controller
        self._environment = environment
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Style").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(MolibooEnvironment.allCases) { e in
                        Button { environment = e.rawValue } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: e.sky, startPoint: .top, endPoint: .bottom))
                                    .overlay(Image(systemName: e.symbol).foregroundStyle(e.isDark ? .white : .primary))
                                    .frame(width: 64, height: 48)
                                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(environment == e.rawValue ? Color.accentColor : .clear, lineWidth: 2))
                                Text(e.title).font(.caption2)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("studio.env.\(e.rawValue)")
                    }
                }
            }
            if controller.isSupported(wardrobeItemID: capID) {
                let on = controller.equipped[capID] != nil
                Button {
                    Task {
                        if on { controller.unequip(wardrobeItemID: capID) } else { await controller.equip(wardrobeItemID: capID) }
                        save()
                    }
                } label: {
                    Label(on ? "Take off Signature Cap" : "Wear Signature Cap", systemImage: on ? "checkmark.circle.fill" : "graduationcap.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(on ? .green : .accentColor)
                .accessibilityIdentifier("studio.style.cap")
            } else {
                Label("No 3D cosmetics fit this Moliboo yet.", systemImage: "info.circle").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    /// Writes through the shared store (ownership-checked), keeping the rest of the outfit.
    private func save() {
        guard let item = MascotWardrobeCatalog.item(id: capID) else { return }
        if controller.equipped[capID] != nil { wardrobe.equip(item) } else if wardrobe.outfit.contains(item) { wardrobe.unequip(item.slot) }
    }
}

/// Photo-mode controls; capture/share arrive with the Photo PR.
struct MolibooPhotoControls: View {
    let characterName: String
    var body: some View {
        Text("Photo mode · \(characterName)")
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 24)
            .accessibilityIdentifier("studio.photo.controls")
    }
}
