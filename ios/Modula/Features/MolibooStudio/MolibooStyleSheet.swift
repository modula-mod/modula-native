import SwiftUI

/// Style sheet (Living Studio). Environment + the Signature Cap quick toggle; the full wardrobe is its own panel.
struct MolibooStyleSheet: View {
    let controller: MolibooSceneController
    @Binding var environment: String
    private var wardrobe = MascotWardrobeStore.shared
    private let capID = MolibooCosmetics.signatureCapID

    var onOutfitChange: () -> Void = {}

    init(controller: MolibooSceneController, environment: Binding<String>, onOutfitChange: @escaping () -> Void = {}) {
        self.controller = controller
        self._environment = environment
        self.onOutfitChange = onOutfitChange
    }

    @State private var pose = MolibooStagePose()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Style").font(.headline)
            positionControls
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
                        onOutfitChange()
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
    /// Character positioning on the stage (size + height), persisted per character.
    private var positionControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Reset lives in its own row so both sliders have the same length.
            HStack {
                Text("Position").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { pose = MolibooStagePose() }.font(.caption.weight(.semibold)).accessibilityIdentifier("studio.pose.reset")
            }
            HStack {
                Label("Size", systemImage: "arrow.up.left.and.arrow.down.right").font(.caption.weight(.semibold)).frame(width: 74, alignment: .leading)
                Slider(value: $pose.scale, in: MolibooStagePose.scaleRange).accessibilityIdentifier("studio.pose.scale")
            }
            HStack {
                Label("Height", systemImage: "arrow.up.and.down").font(.caption.weight(.semibold)).frame(width: 74, alignment: .leading)
                Slider(value: $pose.lift, in: MolibooStagePose.liftRange).accessibilityIdentifier("studio.pose.lift")
            }
        }
        .onAppear { pose = MolibooStagePose.load(for: controller.descriptor.id) }
        .onChange(of: pose) { _, p in p.apply(to: controller); p.save(for: controller.descriptor.id) }
    }
}

/// Photo-mode controls: a shutter. Chrome is hidden while the frame is captured.
struct MolibooPhotoControls: View {
    let characterName: String
    var onCapture: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Button(action: onCapture) {
                ZStack {
                    Circle().fill(.white).frame(width: 66, height: 66)
                    Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                }
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            }
            .accessibilityIdentifier("studio.photo.capture")
            .accessibilityLabel("Take photo of \(characterName)")
            Text("Drag to turn · tap to say hi").font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.top, 10)
        }
        .padding(.bottom, 24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("studio.photo.controls")
    }

}

/// Stage position of the character (Studio "positioning"). Applied to the controller root, so wardrobe follows.
struct MolibooStagePose: Codable, Equatable {
    var scale: Double = 1
    var lift: Double = 0
    static let scaleRange: ClosedRange<Double> = 0.8...1.25
    static let liftRange: ClosedRange<Double> = -0.03...0.03
    static func key(_ id: String) -> String { "moliboo.studio.pose.\(id)" }
    static func load(for id: String, defaults: UserDefaults = .standard) -> MolibooStagePose {
        guard let d = defaults.data(forKey: key(id)), let p = try? JSONDecoder().decode(MolibooStagePose.self, from: d) else { return .init() }
        return p
    }
    func save(for id: String, defaults: UserDefaults = .standard) {
        if let d = try? JSONEncoder().encode(self) { defaults.set(d, forKey: Self.key(id)) }
    }
    @MainActor func apply(to c: MolibooSceneController) {
        c.root.scale = .init(repeating: Float(scale))
        c.root.position.y = Float(lift)
    }
}
