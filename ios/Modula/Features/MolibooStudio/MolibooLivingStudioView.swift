import SwiftUI
import RealityKit

/// MOL-03 Living Studio: a living stage (per-character framing + environment), a header, an action rail
/// (Style / Play / Expressions / Photo) and a contextual sheet. Dev-flagged; reached from Studio and Settings → Moliboo.
struct MolibooLivingStudioView: View {
    let characterID: String

    enum Panel: String, Identifiable, CaseIterable {
        case style, wardrobe, play, expressions
        var id: String { rawValue }
        var title: String { switch self { case .style: "Style"; case .wardrobe: "Wardrobe"; case .play: "Play"; case .expressions: "Expressions" } }
        var symbol: String { switch self { case .style: "paintpalette.fill"; case .wardrobe: "tshirt.fill"; case .play: "gamecontroller.fill"; case .expressions: "face.smiling" } }
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
    @State private var session: MolibooWardrobeSession?
    @State private var capturing = false
    @State private var photo: MolibooCapturedPhoto?
    @State private var shots = 0
    @State private var lastShotSubject = false
    #if DEBUG
    @State private var clipProbe = ""
    #endif
    private var wardrobe = MascotWardrobeStore.shared
    private let capID = MolibooCosmetics.signatureCapID

    private let initialPanel: Panel?
    private let startInPhoto: Bool
    init(characterID: String, initialPanel: Panel? = nil, startInPhoto: Bool = false) {
        self.characterID = characterID; self.initialPanel = initialPanel; self.startInPhoto = startInPhoto
    }

    private var environment: MolibooEnvironment { MolibooEnvironment(rawValue: envRaw) ?? .meadow }
    private var reduceMotion: Bool { systemReduceMotion || forceReduceMotion }
    private var descriptor: MolibooCharacterDescriptor? { MolibooRegistry.manifest?.character(id: characterID) }

    var body: some View {
        let _ = Self._printChanges() // MOLDIAG
        ZStack {
            stageBackground
            VStack(spacing: 0) {
                if !photoMode { header.transition(.move(edge: .top).combined(with: .opacity)) }
                stage
                if !photoMode { rail.transition(.move(edge: .bottom).combined(with: .opacity)) }
            }
            if photoMode && !capturing { photoChrome }
        }
        .animation(reduceMotion ? nil : .snappy, value: photoMode)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: envRaw)
        .toolbar(photoMode ? .hidden : .visible, for: .navigationBar)
        .navigationTitle(descriptor?.displayName ?? "Moliboo")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $panel) { p in panelSheet(p) }
        .sheet(item: $photo) { ph in
            MolibooPhotoPreview(photo: ph, characterName: descriptor?.displayName ?? "Moliboo") { photo = nil }
        }
        #if DEBUG
        .overlay(alignment: .bottomLeading) {
            if let controller { MOL01StateProbe(controller: controller, wardrobeIDs: wardrobe.outfit.equippedIDs) }
            studioProbe
        }
        #endif
        .task { await setUp() }
        .onChange(of: reduceMotion) { _, v in director?.setReduceMotion(v); session?.rig?.reduceMotion = v }
        .onChange(of: scenePhase) { _, p in director?.setPaused(p != .active) }
        .onChange(of: panel) { _, p in director?.setPaused(Self.holdsStill(p)); frame(sheetOpen: p != nil, animated: true) }
        .onDisappear { director?.stop(); session?.rig?.stop(); controller?.stop() }
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
            MolibooPhotoControls(characterName: descriptor?.displayName ?? "Moliboo") { Task { await capture() } }
        }
    }


    /// Trying things on / posing: the idle personality holds still.
    private static func holdsStill(_ p: Panel?) -> Bool {
        guard let p else { return false }
        return p == .style || p == .wardrobe || p == .expressions
    }

    /// Per-character framing; with a sheet up the camera tilts down and pulls back so the Moliboo sits above the sheet.
    private func frame(sheetOpen: Bool, animated: Bool) {
        guard let c = controller else { return }
        let f = MolibooFraming.for(characterID)
        c.cameraEntity.camera.fieldOfViewInDegrees = f.fov
        let shift: SIMD3<Float> = sheetOpen ? [0, -(f.eye.z * 0.26), f.eye.z * 0.2] : .zero
        let probe = Entity()
        probe.look(at: f.target + [0, shift.y, 0], from: f.eye + shift, relativeTo: nil)
        if animated && !reduceMotion {
            c.cameraEntity.move(to: probe.transform, relativeTo: nil, duration: 0.35, timingFunction: .easeInOut)
        } else {
            c.cameraEntity.transform = probe.transform
        }
    }

    /// Hide every piece of chrome, let a frame render, snapshot the window, then show the share preview.
    private func capture() async {
        capturing = true
        try? await Task.sleep(for: .milliseconds(250))
        let img = MolibooPhotoCapture.captureKeyWindow()
        capturing = false
        guard let img else { return }
        shots += 1
        lastShotSubject = MolibooPhotoCapture.showsSubject(img)
        photo = MolibooCapturedPhoto(image: img)
    }

    private func panelSheet(_ p: Panel) -> some View {
        VStack(spacing: 0) {
            // The sheet covers the rail, so it carries its own panel switcher.
            Picker("Panel", selection: Binding(get: { p }, set: { panel = $0 })) {
                ForEach(Panel.allCases) { q in Label(q.title, systemImage: q.symbol).tag(q) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("studio.sheet.tabs")
            .safeAreaInset(edge: .trailing) {
                Button { panel = nil } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary) }
                    .accessibilityIdentifier("studio.sheet.close").accessibilityLabel("Close")
            }
            .padding(.horizontal, 20).padding(.top, 16)
            sheet(for: p)
            Spacer(minLength: 0)
        }
        .presentationDetents(p == .wardrobe ? [.medium, .large] : [.height(300), .medium])
        .presentationBackgroundInteraction(.enabled(upThrough: p == .wardrobe ? .medium : .height(300)))
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder private func sheet(for p: Panel) -> some View {
        switch p {
        case .style: styleSheet
        case .wardrobe:
            if let controller, let session { MolibooWardrobeSheet(controller: controller, session: session) }
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
            MolibooStyleSheet(controller: controller, environment: $envRaw) { session?.resync() }
        }
    }

    // MARK: Setup

    private func setUp() async {
        guard controller == nil else { return }
        guard let m = MolibooRegistry.manifest, let d = MolibooRegistry.descriptor(for: characterID, manifest: m) else { unavailable = true; return }
        let c = MolibooSceneController(descriptor: d)
        c.cosmetics = m.cosmetics
        controller = c
        frame(sheetOpen: false, animated: false)
        let ws = MolibooWardrobeSession(store: wardrobe)
        session = ws
        await c.load()
        await c.sync(outfitItemIDs: wardrobe.outfit.equippedIDs)
        if !c.loadFailed {
            let rig = MolibooWardrobeRig(controller: c)
            rig.reduceMotion = reduceMotion
            ws.rig = rig
            await rig.sync(wardrobe.outfit.equippedIDs.filter { !c.isSupported(wardrobeItemID: $0) })
        }
        let dir = MolibooStudioDirector(controller: c, reduceMotion: reduceMotion)
        director = dir
        if !c.loadFailed { dir.start() }
        MolibooStagePose.load(for: d.id).apply(to: c)
        if startInPhoto { photoMode = true } else if let initialPanel { panel = initialPanel }
        #if DEBUG
        if let clip = MOL03DebugHarness.arg("-MOL03Clip") { await measureClip(clip, controller: c, director: dir) }
        switch MOL03DebugHarness.panel {
        case "photo": photoMode = true
        case let p?: panel = Panel(rawValue: p)
        case nil: break
        }
        #endif
    }

    #if DEBUG
    /// Plays one clip on the live stage and reports which entities (rigid parts) or skeleton joints actually moved.
    private func measureClip(_ clip: String, controller c: MolibooSceneController, director dir: MolibooStudioDirector) async {
        guard let root = c.character else { clipProbe = " clip=\(clip) played=0"; return }
        dir.setPaused(true)
        try? await Task.sleep(for: .milliseconds(400))
        func snapshot() -> [String: [Float]] {
            var out: [String: [Float]] = [:]
            func walk(_ e: Entity, _ path: String) {
                let t = e.transform
                let w = e.position(relativeTo: nil)
                out[path + e.name] = [t.translation.x, t.translation.y, t.translation.z, t.rotation.vector.x, t.rotation.vector.y, t.rotation.vector.z, t.rotation.vector.w, t.scale.x, t.scale.y, t.scale.z, w.x, w.y, w.z]
                if let m = e as? ModelEntity, !m.jointNames.isEmpty {
                    for (i, j) in m.jointTransforms.enumerated() {
                        out["joint:" + e.name + "/" + (m.jointNames[i].split(separator: "/").last.map(String.init) ?? "\(i)")] =
                            [j.translation.x, j.translation.y, j.translation.z, j.rotation.vector.x, j.rotation.vector.y, j.rotation.vector.z, j.rotation.vector.w, j.scale.x, j.scale.y, j.scale.z]
                    }
                }
                for ch in e.children { walk(ch, path) }
            }
            walk(root, "")
            return out
        }
        var played = false
        var moved: [String: Float] = [:]
        // Up to 3 attempts: right after load RealityKit may not yet have applied the first animation frame.
        for _ in 0..<3 where moved.isEmpty {
            let before = snapshot()
            played = c.playClip(clip, loop: true)
            for _ in 0..<16 {
                try? await Task.sleep(for: .milliseconds(100))
                for (k, v) in snapshot() {
                    guard let b = before[k] else { continue }
                    let d = zip(v, b).map { abs($0 - $1) }.max() ?? 0
                    if d > 1e-4 { moved[k] = max(moved[k] ?? 0, d) }
                }
            }
        }
        let names = moved.keys.filter { !$0.hasPrefix("anchor_") }.sorted { moved[$0]! > moved[$1]! }.prefix(10)
            .map { $0.replacingOccurrences(of: " ", with: "_") }
        clipProbe = " clip=\(clip) played=\(played ? 1 : 0) moved=\(moved.count) parts=\(names.joined(separator: ","))"
    }

    private var studioProbe: some View {
        let w = "wpv=\(session?.isPreviewing == true ? 1 : 0) wprev=\(session?.previewIDs.sorted().joined(separator: ",") ?? "") wsaved=\(wardrobe.outfit.equippedIDs.sorted().joined(separator: ",")) wundo=\(wardrobe.canUndo ? 1 : 0) wpresets=\(wardrobe.presets.count) wblocked=\(session?.blocked.count ?? 0) shots=\(shots) subject=\(lastShotSubject ? 1 : 0)"
        let v = w + clipProbe + " char=\(characterID) env=\(environment.rawValue) panel=\(panel?.rawValue ?? "none") photo=\(photoMode ? 1 : 0) reactions=\(director?.reactionCount ?? 0) idle=\(director?.idleFired ?? 0) react=\(director?.lastReaction ?? "") nap=\(director?.napping == true ? 1 : 0) rm=\(reduceMotion ? 1 : 0) paused=\(director?.paused == true ? 1 : 0)"
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
