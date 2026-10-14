import SwiftUI
import RealityKit

/// MOL-03 Living Studio: a living stage (per-character framing + environment), a header, an action rail
/// (Style / Play / Expressions / Photo) and a contextual sheet. Dev-flagged; reached from Studio and Settings → Moliboo.
struct MolibooLivingStudioView: View {
    let characterID: String

    enum Panel: String, Identifiable, CaseIterable {
        case style, play, expressions
        var id: String { rawValue }
        var title: String { switch self { case .style: "Style"; case .play: "Play"; case .expressions: "Expressions" } }
        var symbol: String { switch self { case .style: "tshirt.fill"; case .play: "gamecontroller.fill"; case .expressions: "face.smiling" } }
    }

    @AppStorage("moliboo.studio.environment") private var envRaw = MolibooEnvironment.meadow.rawValue
    /// Test/debug hook so XCUITest can exercise the Reduced Motion path (the system toggle is not scriptable).
    @AppStorage("moliboo.studio.forceReduceMotion") private var forceReduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller: MolibooSceneController?
    @State private var director: MolibooStudioDirector?
    @State private var unavailable = false
    @State private var panel: Panel?
    @State private var photoMode = false
    @State private var dragStart: Float = 0
    private var wardrobe = MascotWardrobeStore.shared
    private let capID = MolibooCosmetics.signatureCapID

    init(characterID: String) { self.characterID = characterID }

    private var environment: MolibooEnvironment { MolibooEnvironment(rawValue: envRaw) ?? .meadow }
    private var reduceMotion: Bool { systemReduceMotion || forceReduceMotion }
    private var descriptor: MolibooCharacterDescriptor? { MolibooRegistry.manifest?.character(id: characterID) }

    var body: some View {
        ZStack {
            stageBackground
            VStack(spacing: 0) {
                if !photoMode { header.transition(.move(edge: .top).combined(with: .opacity)) }
                stage
                if !photoMode { rail.transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
            if photoMode { photoChrome }
        }
        .animation(reduceMotion ? nil : .snappy, value: photoMode)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: envRaw)
        .toolbar(photoMode ? .hidden : .visible, for: .navigationBar)
        .navigationTitle(descriptor?.displayName ?? "Moliboo")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $panel) { p in
            sheet(for: p)
                .presentationDetents([.height(270), .medium])
                .presentationBackgroundInteraction(.enabled(upThrough: .height(270)))
                .presentationDragIndicator(.visible)
        }
        #if DEBUG
        .overlay(alignment: .bottomLeading) {
            if let controller { MOL01StateProbe(controller: controller, wardrobeIDs: wardrobe.outfit.equippedIDs) }
            studioProbe
        }
        #endif
        .task { await setUp() }
        .onChange(of: reduceMotion) { _, v in director?.setReduceMotion(v) }
        .onChange(of: scenePhase) { _, p in director?.setPaused(p != .active) }
        .onChange(of: panel) { _, p in director?.setPaused(p == .style) }   // trying things on: hold still
        .onDisappear { director?.stop(); controller?.stop() }
    }

    // MARK: Pieces

    private var stageBackground: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: environment.sky, startPoint: .top, endPoint: .bottom)
            Ellipse().fill(environment.floor.opacity(0.85)).frame(height: 220).offset(y: 90).blur(radius: 18)
            if environment == .nightSky { StarField().allowsHitTesting(false) }
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("studio.environment.\(environment.rawValue)")
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor?.displayName ?? "Moliboo").font(.title2.weight(.bold))
                if let d = descriptor {
                    Text("#\(String(format: "%03d", d.canonicalNumber)) · \(director?.personality.mood.capitalized ?? "")")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                Picker("Environment", selection: $envRaw) {
                    ForEach(MolibooEnvironment.allCases) { e in Label(e.title, systemImage: e.symbol).tag(e.rawValue) }
                }
            } label: {
                Label(environment.title, systemImage: environment.symbol)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .accessibilityIdentifier("studio.envMenu")
        }
        .foregroundStyle(environment.isDark ? .white : .primary)
        .padding(.horizontal, 18).padding(.top, 8)
    }

    @ViewBuilder private var stage: some View {
        ZStack {
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
                .simultaneousGesture(TapGesture().onEnded { director?.request(.tap) })
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in director?.request(.pet) })
                .accessibilityIdentifier("moliboo3d.view")
                .accessibilityLabel("\(descriptor?.displayName ?? "Moliboo"). Tap to say hi, hold to pet, drag to turn.")
            } else if unavailable || controller?.loadFailed == true {
                fallback2D.accessibilityIdentifier("moliboo3d.fallback2d")
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var fallback2D: some View {
        if let kind = ModulaMascotKind(rawValue: characterID) {
            ModulaMascotFigure(kind: kind, pose: .still(), size: 120, outfit: wardrobe.outfit)
        } else {
            Image(systemName: "pawprint").font(.system(size: 60))
        }
    }

    private var rail: some View {
        HStack(spacing: 10) {
            ForEach(Panel.allCases) { p in
                railButton(p.title, p.symbol, id: "studio.rail.\(p.rawValue)", selected: panel == p) { panel = panel == p ? nil : p }
            }
            railButton("Photo", "camera.fill", id: "studio.rail.photo", selected: false) { panel = nil; photoMode = true }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 14).padding(.bottom, 8)
    }

    private func railButton(_ title: String, _ symbol: String, id: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption2.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(selected ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var photoChrome: some View {
        VStack {
            HStack {
                Spacer()
                Button("Done") { photoMode = false }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("studio.photo.done")
            }
            .padding()
            Spacer()
            MolibooPhotoControls(characterName: descriptor?.displayName ?? "Moliboo")
        }
    }

    @ViewBuilder private func sheet(for p: Panel) -> some View {
        switch p {
        case .style: styleSheet
        case .play: playSheet
        case .expressions: expressionsSheet
        }
    }

    private var playSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Play").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                ForEach(MolibooPlay.allCases) { play in
                    Button { director?.request(play.reaction) } label: {
                        Label(play.title, systemImage: play.symbol).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("studio.play.\(play.rawValue)")
                }
            }
            Text(director?.napping == true ? "Shh… tap the stage to wake them up." : "Tap to say hi, hold to pet, drag to turn.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private var expressionsSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Expressions").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 10) {
                ForEach(MolibooExpression.allCases, id: \.self) { e in
                    Button(e.title) {
                        if e == .blink { controller?.blink() } else { controller?.setExpression(e) }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("studio.expr.\(e.rawValue)")
                }
            }
        }
        .padding(20)
    }

    @ViewBuilder private var styleSheet: some View {
        if let controller {
            MolibooStyleSheet(controller: controller, environment: $envRaw)
        }
    }

    // MARK: Setup

    private func setUp() async {
        guard controller == nil else { return }
        guard let m = MolibooRegistry.manifest, let d = MolibooRegistry.descriptor(for: characterID, manifest: m) else { unavailable = true; return }
        let c = MolibooSceneController(descriptor: d)
        c.cosmetics = m.cosmetics
        let f = MolibooFraming.for(d.id)
        c.cameraEntity.camera.fieldOfViewInDegrees = f.fov
        c.cameraEntity.look(at: f.target, from: f.eye, relativeTo: nil)
        controller = c
        await c.load()
        await c.sync(outfitItemIDs: wardrobe.outfit.equippedIDs)
        let dir = MolibooStudioDirector(controller: c, reduceMotion: reduceMotion)
        director = dir
        if !c.loadFailed { dir.start() }
    }

    #if DEBUG
    private var studioProbe: some View {
        let v = "char=\(characterID) env=\(environment.rawValue) panel=\(panel?.rawValue ?? "none") photo=\(photoMode ? 1 : 0) reactions=\(director?.reactionCount ?? 0) idle=\(director?.idleFired ?? 0) react=\(director?.lastReaction ?? "") nap=\(director?.napping == true ? 1 : 0) rm=\(reduceMotion ? 1 : 0) paused=\(director?.paused == true ? 1 : 0)"
        return Text(v).font(.system(size: 1)).opacity(0.01).frame(width: 1, height: 1)
            .accessibilityIdentifier("studio.state").accessibilityLabel(v)
    }
    #endif
}

/// Night-sky sparkle (static positions; no animation under Reduced Motion because it never moves).
private struct StarField: View {
    var body: some View {
        Canvas { ctx, size in
            for i in 0..<60 {
                let x = CGFloat((i * 73) % 997) / 997 * size.width
                let y = CGFloat((i * 131) % 991) / 991 * size.height * 0.6
                let r = CGFloat(1 + (i % 3))
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.4 + Double(i % 5) / 10)))
            }
        }
    }
}

/// Studio entry point (dev flag): opens the Living Studio for any 3D-capable character.
struct MolibooLivingStudioEntryButton: View {
    let characterID: String
    var body: some View {
        NavigationLink { MolibooLivingStudioView(characterID: characterID) } label: {
            Label("Open 3D Studio · \(MolibooRegistry.descriptor(for: characterID)?.displayName ?? "Moliboo") (dev)", systemImage: "cube.transparent")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("moliboo3d.entry")
    }
}
