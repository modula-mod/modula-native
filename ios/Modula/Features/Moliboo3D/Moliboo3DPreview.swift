import SwiftUI
import RealityKit

/// Interactive 3D Pebble preview (MOL-01). Uses the shared wardrobe store, so saving here = saving the outfit everywhere.
struct Moliboo3DPreview: View {
    @State private var controller: MolibooSceneController?
    @State private var dragStart: Float = 0
    @State private var manifestError = false
    private var wardrobe = MascotWardrobeStore.shared
    private let hatID = MolibooCosmetics.signatureCapID

    private let debugScene: String?
    init(debugScene: String? = nil) { self.debugScene = debugScene }

    var body: some View {
        VStack(spacing: 14) {
            // Official Moliboos wordmark: exact vector asset, never redrawn or typeset.
            Image("MoliboosLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 34)
                .accessibilityLabel("Moliboos")
                .accessibilityIdentifier("moliboo3d.logo")
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.62, green: 0.70, blue: 0.80).opacity(0.45), .primary.opacity(0.04)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                if let controller, !controller.loadFailed {
                    RealityView { content in
                        content.add(controller.root)
                        content.add(controller.cameraEntity)
                        content.camera = .virtual
                    }
                    .gesture(DragGesture()
                        .onChanged { v in controller.yaw = dragStart + Float(v.translation.width) * 0.012 }
                        .onEnded { _ in dragStart = controller.yaw })
                    .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { _ in controller.react() })
                    .accessibilityIdentifier("moliboo3d.view")
                } else if manifestError || controller?.loadFailed == true {
                    // Fallback: existing 2D renderer
                    ModulaMascotFigure(kind: .pebble, pose: .still(), size: 80, outfit: wardrobe.outfit)
                        .accessibilityIdentifier("moliboo3d.fallback2d")
                } else {
                    ProgressView()
                }
            }
            .frame(height: 320)

            if let controller {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(MolibooExpression.allCases, id: \.self) { e in
                            Button(e.title) { controller.setExpression(e) }.buttonStyle(.bordered)
                        }
                    }
                }
                HStack {
                    Button("Wobble") { controller.wobble() }
                    Button("Idle bob") { controller.playClip("idle_bob") }
                    Button("Bounce") { controller.bounce() }
                    Button("React") { controller.react() }
                }.buttonStyle(.bordered)

                let hatOn = controller.equipped[hatID] != nil
                HStack {
                    Button(hatOn ? "Remove cap" : "Equip Signature Cap") {
                        Task {
                            if hatOn { controller.unequip(wardrobeItemID: hatID) } else { await controller.equip(wardrobeItemID: hatID) }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("moliboo3d.hatToggle")
                    Button("Save outfit") { save(controller) }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("moliboo3d.save")
                }
            }
        }
        .padding(16)
        .navigationTitle("Pebble 3D")
        .navigationBarTitleDisplayMode(.inline)
        .task { await setUp() }
        .onDisappear { controller?.stop() }
    }

    private func setUp() async {
        guard controller == nil else { return }
        guard let m = try? MolibooManifest.bundled(), let d = m.character(id: "pebble") else { manifestError = true; return }
        let c = MolibooSceneController(descriptor: d)
        c.cosmetics = m.cosmetics
        controller = c
        await c.load()
        await c.sync(outfitItemIDs: wardrobe.outfit.equippedIDs)
        if let debugScene { await apply(debugScene: debugScene, to: c) }
    }

    /// Deterministic states for MOL-01 evidence screenshots (see scripts/mol01_screenshots.sh).
    private func apply(debugScene: String, to c: MolibooSceneController) async {
        switch debugScene {
        case "front": c.setExpression(.idle)
        case "three_quarter": c.yaw = 0.7; dragStart = c.yaw
        case "back": c.yaw = .pi; dragStart = c.yaw
        case "happy": c.setExpression(.happy)
        case "excited": c.setExpression(.excited)
        case "sleepy": c.setExpression(.sleepy)
        case "surprised": c.setExpression(.surprised)
        case "hat_on": await c.equip(wardrobeItemID: hatID)
        case "hat_off": await c.equip(wardrobeItemID: hatID); c.unequip(wardrobeItemID: hatID)
        case "save_hat": await c.equip(wardrobeItemID: hatID); save(c)
        case "reopen": break   // relaunch after save_hat: hat must come back from the persisted outfit
        case "clear_hat": c.unequip(wardrobeItemID: hatID); save(c)
        default: break
        }
    }

    /// Only eligible (compatible + owned) items are written, through the existing store; the rest of the outfit is preserved.
    private func save(_ c: MolibooSceneController) {
        guard let item = MascotWardrobeCatalog.item(id: hatID), c.isSupported(wardrobeItemID: hatID) else { return }
        if c.equipped[hatID] != nil { wardrobe.equip(item) }
        else if wardrobe.outfit.contains(item) { wardrobe.unequip(item.slot) }
    }
}

/// Studio entry point; shown only for Pebble when the dev flag is on.
struct Moliboo3DEntryButton: View {
    var body: some View {
        NavigationLink { Moliboo3DPreview() } label: {
            Label("Open 3D Pebble (dev)", systemImage: "cube.transparent")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("moliboo3d.entry")
    }
}
