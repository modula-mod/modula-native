import SwiftUI
import RealityKit

/// Interactive 3D Moliboo preview (MOL-01/02), for any character the registry marks 3D-capable. Uses the shared wardrobe store, so saving here = saving the outfit everywhere.
struct Moliboo3DPreview: View {
    @State private var controller: MolibooSceneController?
    @State private var dragStart: Float = 0
    @State private var manifestError = false
    private var wardrobe = MascotWardrobeStore.shared
    private let hatID = MolibooCosmetics.signatureCapID

    private let debugScene: String?
    let characterID: String
    init(characterID: String, debugScene: String? = nil) { self.characterID = characterID; self.debugScene = debugScene }
    private var displayName: String { MolibooRegistry.manifest?.character(id: characterID)?.displayName ?? "Moliboo" }

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
                        controller.frameSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak controller] ev in
                            MainActor.assumeIsolated { controller?.recordFrame(ev.deltaTime) }
                        }
                    }
                    .gesture(DragGesture()
                        .onChanged { v in controller.yaw = dragStart + Float(v.translation.width) * 0.012 }
                        .onEnded { _ in dragStart = controller.yaw })
                    .simultaneousGesture(TapGesture().onEnded { controller.react() })   // tap Pebble (whole 3D stage; entity hit-test is unreliable with a custom virtual camera)
                    .accessibilityIdentifier("moliboo3d.view")
                } else if manifestError || controller?.loadFailed == true {
                    // Fallback: existing 2D renderer
                    Group {
                        if let kind = ModulaMascotKind(rawValue: characterID) {
                            ModulaMascotFigure(kind: kind, pose: .still(), size: 80, outfit: wardrobe.outfit)
                        } else {
                            Image(systemName: "pawprint").font(.largeTitle)
                        }
                    }
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
        #if DEBUG
        .overlay(alignment: .bottomLeading) { if let controller { MOL01StateProbe(controller: controller, wardrobeIDs: wardrobe.outfit.equippedIDs) } }
        #endif
        .padding(16)
        .navigationTitle("\(displayName) 3D")
        .navigationBarTitleDisplayMode(.inline)
        .task { await setUp() }
        .onDisappear { controller?.stop() }
    }

    private func setUp() async {
        if controller?.isStopped == true { controller = nil }   // re-shown after teardown: build a fresh scene
        guard controller == nil else { return }
        guard let m = MolibooRegistry.manifest, let d = MolibooRegistry.descriptor(for: characterID, manifest: m) else { manifestError = true; return }
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

/// Studio entry point; shown for any 3D-capable character when the dev flag is on.
struct Moliboo3DEntryButton: View {
    let characterID: String
    var body: some View {
        NavigationLink { Moliboo3DPreview(characterID: characterID) } label: {
            Label("Open 3D \(MolibooRegistry.descriptor(for: characterID)?.displayName ?? "Moliboo") (dev)", systemImage: "cube.transparent")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("moliboo3d.entry")
    }
}
