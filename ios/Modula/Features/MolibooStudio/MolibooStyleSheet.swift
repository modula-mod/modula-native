import SwiftUI

/// Style sheet (Living Studio). Scene backgrounds from `MolibooEnvironment` + optional Signature Cap / pose.
struct MolibooStyleSheet: View {
    var controller: MolibooSceneController?
    @Binding var environment: String
    private var wardrobe = MascotWardrobeStore.shared
    private let capID = MolibooCosmetics.signatureCapID
    var onOutfitChange: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(controller: MolibooSceneController?, environment: Binding<String>, onOutfitChange: @escaping () -> Void = {}) {
        self.controller = controller
        self._environment = environment
        self.onOutfitChange = onOutfitChange
    }

    @State private var pose = MolibooStagePose()

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Scene").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(MolibooEnvironment.allCases) { e in
                            Button { environment = e.rawValue } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(LinearGradient(colors: e.sky, startPoint: .top, endPoint: .bottom))
                                        .overlay {
                                            Image(systemName: e.symbol)
                                                .font(.title2.weight(.semibold))
                                                .foregroundStyle(e.isDark ? .white : .primary.opacity(0.85))
                                        }
                                        .frame(height: 88)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .strokeBorder(environment == e.rawValue ? Color.accentColor : Color.primary.opacity(0.06),
                                                              lineWidth: environment == e.rawValue ? 2 : 0.5)
                                        )
                                    Text(e.title).font(.subheadline.weight(.semibold))
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("studio.env.\(e.rawValue)")
                            .accessibilityAddTraits(environment == e.rawValue ? .isSelected : [])
                        }
                    }
                }

                if let controller, controller.isSupported(wardrobeItemID: capID) {
                    let on = controller.equipped[capID] != nil
                    Button {
                        Task {
                            if on { controller.unequip(wardrobeItemID: capID) } else { await controller.equip(wardrobeItemID: capID) }
                            save(controller)
                            onOutfitChange()
                        }
                    } label: {
                        Label(on ? "Take off Signature Cap" : "Wear Signature Cap",
                              systemImage: on ? "checkmark.circle.fill" : "graduationcap.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: Capsule(), interactive: true, tint: on ? .green.opacity(0.25) : Color.primary.opacity(0.04), specular: true)
                    .accessibilityIdentifier("studio.style.cap")
                }

                if let controller {
                    positionControls(controller)
                }
            }
            .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 36)
        }
    }

    private func save(_ controller: MolibooSceneController) {
        guard let item = MascotWardrobeCatalog.item(id: capID) else { return }
        if controller.equipped[capID] != nil { wardrobe.equip(item) } else if wardrobe.outfit.contains(item) { wardrobe.unequip(item.slot) }
    }

    private func positionControls(_ controller: MolibooSceneController) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Position").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { pose = MolibooStagePose() }
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("studio.pose.reset")
            }
            HStack {
                Text("Size").font(.caption.weight(.semibold)).frame(width: 56, alignment: .leading)
                Slider(value: $pose.scale, in: MolibooStagePose.scaleRange).accessibilityIdentifier("studio.pose.scale")
            }
            HStack {
                Text("Height").font(.caption.weight(.semibold)).frame(width: 56, alignment: .leading)
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
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            }
            .accessibilityIdentifier("studio.photo.capture")
            .accessibilityLabel("Take photo of \(characterName)")
            Text("Tap to say hi · hold to pet").font(.caption.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .modulaGlass(in: Capsule(), interactive: false, specular: false)
                .padding(.top, 10)
        }
        .padding(.bottom, 28)
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
