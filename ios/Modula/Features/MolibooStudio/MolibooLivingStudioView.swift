import SwiftUI
import RealityKit

/// MOL-03R Living Studio: persistent 3D stage (per-character framing + environment shaders + volumetric halo),
/// crisp header, floating Liquid Glass action rail, and non-blocking sheets (Compact / Medium / 76% Expanded)
/// so the active Moliboo remains visible on stage at all times.
struct MolibooLivingStudioView: View {
    let characterID: String

    enum Panel: String, Identifiable, CaseIterable {
        case wardrobe, style, faces
        var id: String { rawValue }
        var title: String {
            switch self {
            case .style: "Style"
            case .wardrobe: "Wardrobe"
            case .faces: "Faces"
            }
        }
        var symbol: String {
            switch self {
            case .style: "paintpalette.fill"
            case .wardrobe: "tshirt.fill"
            case .faces: "face.smiling"
            }
        }
    }

    @AppStorage("moliboo.studio.environment") private var envRaw = MolibooEnvironment.meadow.rawValue
    /// Test/debug hook so XCUITest can exercise the Reduced Motion path (the system toggle is not scriptable).
    @AppStorage("moliboo.studio.forceReduceMotion") private var forceReduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller: MolibooSceneController?
    @State private var stageRevealed = false
    @Environment(\.dismiss) private var dismissStudio
    @State private var director: MolibooStudioDirector?
    @State private var unavailable = false
    @State private var panel: Panel?
    @State private var detent: PresentationDetent = .medium
    @Namespace private var segmentNS
    @State private var photoMode = false
    @State private var dragStart: Float = 0
    @State private var session: MolibooWardrobeSession?
    @State private var capturing = false
    @State private var photo: MolibooCapturedPhoto?
    @State private var shots = 0
    @State private var lastShotSubject = false
    @State private var pulseTick = 0
    @State private var hopUntil = Date.distantPast
    #if DEBUG
    @State private var clipProbe = ""
    #endif
    private var wardrobe = MascotWardrobeStore.shared
    private let capID = MolibooCosmetics.signatureCapID
    private let teal = Color(red: 0.21, green: 0.61, blue: 0.67)

    private let initialPanel: Panel?
    private let startInPhoto: Bool
    private let moreTab: MascotStudioView.StudioTab
    init(characterID: String, initialPanel: Panel? = nil, startInPhoto: Bool = false, moreTab: MascotStudioView.StudioTab = .rewards) {
        self.characterID = characterID; self.initialPanel = initialPanel; self.startInPhoto = startInPhoto; self.moreTab = moreTab
        // Start in photo mode from the first frame (no flash of the normal Studio chrome).
        _photoMode = State(initialValue: startInPhoto)
    }

    private var environment: MolibooEnvironment { MolibooEnvironment(rawValue: envRaw) ?? .meadow }
    private var reduceMotion: Bool { systemReduceMotion || forceReduceMotion }
    private var descriptor: MolibooCharacterDescriptor? { MolibooRegistry.manifest?.character(id: characterID) }
    private var accentColor: Color { ModulaMascotKind(rawValue: characterID)?.palette.accent ?? teal }

    var body: some View {
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
        // Studio and Photo mode own the screen: no global tab bar under them.
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismissStudio() } label: {
                    Image(systemName: "chevron.left").font(.headline)
                        .foregroundStyle(environment.isDark ? .white : .black)
                        .frame(width: 36, height: 36)
                }
                .modulaGlass(in: Circle(), interactive: true, specular: true)
                .accessibilityLabel("Back")
                .accessibilityIdentifier("studio.back")
            }
        }
        .navigationTitle(descriptor?.displayName ?? "Moliboo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(environment.isDark ? .dark : .light, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
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
        .onChange(of: panel) { _, p in
            director?.setPaused(Self.holdsStill(p))
            frame(sheetOpen: p != nil, animated: true)
        }
        .onDisappear { director?.stop(); session?.rig?.stop(); controller?.stop() }
    }

    // MARK: Pieces

    private var stageBackground: some View {
        let live = !photoMode && !reduceMotion && scenePhase == .active
        return ZStack(alignment: .bottom) {
            LinearGradient(colors: environment.sky, startPoint: .top, endPoint: .bottom)
            switch environment {
            case .nightSky:
                Color.clear.molibooNebula(0.85, animated: live)
                MolibooAmbientBackground(ambience: .night, animated: live, showsSky: false)
            case .meadow:
                Color.clear.molibooSunbeams(Color(red: 1.0, green: 0.97, blue: 0.82), intensity: 0.85, animated: live)
                MolibooAmbientBackground(ambience: .afternoon, animated: live, showsSky: false, density: 0.7)
            case .cozyRoom:
                Color.clear.molibooSunbeams(Color(red: 1.0, green: 0.88, blue: 0.72), intensity: 0.75, animated: live)
                MolibooAmbientBackground(ambience: .dreamy, animated: live, showsSky: false, density: 0.6)
            case .studio:
                RadialGradient(colors: [.white.opacity(0.6), .clear], center: .center, startRadius: 10, endRadius: 320)
            }
            // Soft floor only — no clipped arches / heavy aura. Effects pause under Reduce Motion.
            if live {
                Circle()
                    .fill(accentColor.opacity(environment.isDark ? 0.18 : 0.10))
                    .frame(width: 280, height: 280)
                    .blur(radius: 40)
                    .offset(y: -70)
                    .allowsHitTesting(false)
            }
            Ellipse()
                .fill(Color.primary.opacity(environment.isDark ? 0.35 : 0.12))
                .frame(width: 200, height: 28)
                .offset(y: 100)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("studio.environment.\(environment.rawValue)")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.title2.weight(.bold))
                Text(headerCaption)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            // Scene lives in Style sheet; keep a quiet glass shortcut here.
            Menu {
                ForEach(MolibooEnvironment.allCases) { e in
                    Button { envRaw = e.rawValue } label: {
                        Label(e.title, systemImage: e == environment ? "checkmark" : e.symbol)
                    }
                }
            } label: {
                Image(systemName: environment.symbol)
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .modulaGlass(in: Circle(), interactive: true, specular: true)
            }
            .accessibilityLabel("Scene, \(environment.title)")
            .accessibilityIdentifier("studio.envMenu")
        }
        .foregroundStyle(environment.isDark ? .white : .primary)
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 4)
    }

    private var displayName: String {
        descriptor?.displayName ?? ModulaMascotKind(rawValue: characterID)?.name ?? "Moliboo"
    }
    private var headerCaption: String {
        // The 2D catalogue number is canonical (sheets win); the 3D descriptor only as a fallback.
        if let k = ModulaMascotKind(rawValue: characterID) { return String(format: "#%03d · Studio", k.number) }
        if let d = descriptor { return String(format: "#%03d · Studio", d.canonicalNumber) }
        return "Studio"
    }

    @ViewBuilder private var stage: some View {
        ZStack {
            if !MolibooFeatureFlags.native3DEnabled {
                stage2D.accessibilityIdentifier("moliboo2d.stage")
            } else if let controller, !controller.loadFailed {
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
                .simultaneousGesture(TapGesture().onEnded { director?.request(.tap); pulseTick += 1 })
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in director?.request(.pet); pulseTick += 1 })
                .accessibilityIdentifier("moliboo3d.view")
                // RealityView's first frames are black: fade the stage in once it has rendered.
                .opacity(stageRevealed ? 1 : 0)
                .task {
                    try? await Task.sleep(for: .milliseconds(350))
                    withAnimation(.easeOut(duration: 0.35)) { stageRevealed = true }
                }
                .accessibilityLabel("\(descriptor?.displayName ?? "Moliboo"). Tap to say hi, hold to pet.")
            } else if unavailable || controller?.loadFailed == true {
                fallback2D.accessibilityIdentifier("moliboo3d.fallback2d")
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 2D-only stage: the 2D renderer in the live try-on outfit (hat fit comes from the 2D rig), mood from the
    /// Expressions panel, a breathing bob, a hop on tap, and a soft elliptical contact shadow on the floor.
    @ViewBuilder private var stage2D: some View {
        if let kind = ModulaMascotKind(rawValue: characterID) {
            let s: CGFloat = 150
            let live = !photoMode || !reduceMotion
            TimelineView(.animation(paused: reduceMotion || scenePhase != .active || !live)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                let breathe = reduceMotion ? 0 : CGFloat(sin(t * 2 * .pi / 3.2))
                let hopUp = max(0, hopUntil.timeIntervalSince(tl.date)) / 0.45
                let hop = reduceMotion ? 0 : CGFloat(sin(hopUp * .pi)) * 26
                ZStack {
                    Ellipse()
                        .fill(Color.primary.opacity(environment.isDark ? 0.28 : 0.14))
                        .frame(width: s * 1.15 * (1 - hop / 160), height: s * 0.22)
                        .offset(y: s * 0.62)
                    ModulaMascotFigure(kind: kind, pose: .still(Self.mood(controller?.expression ?? .idle)), size: s,
                                       outfit: session?.preview ?? wardrobe.outfit)
                        .scaleEffect(x: 1 - breathe * 0.01, y: 1 + breathe * 0.015, anchor: .bottom)
                        .offset(y: -hop)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { hopUntil = .now.addingTimeInterval(0.45); pulseTick += 1; controller?.setExpression(.happy) }
            .onLongPressGesture(minimumDuration: 0.5) { pulseTick += 1; controller?.setExpression(.excited) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(descriptor?.displayName ?? "Moliboo"). Tap to say hi, hold to pet.")
            .accessibilityAddTraits(.isButton)
        } else {
            fallback2D
        }
    }

    private static func mood(_ e: MolibooExpression) -> MascotMood {
        switch e {
        case .idle, .blink: .idle
        case .happy: .happy
        case .excited: .excited
        case .surprised: .surprised
        case .sleepy: .sleepy
        case .sad: .sad
        }
    }

    @ViewBuilder private var fallback2D: some View {
        if let kind = ModulaMascotKind(rawValue: characterID) {
            ModulaMascotFigure(kind: kind, pose: .still(), size: 120, outfit: wardrobe.outfit)
        } else {
            Image(systemName: "pawprint").font(.system(size: 60))
        }
    }

    private var rail: some View {
        HStack(spacing: 6) {
            ForEach(Panel.allCases) { p in
                railButton(p.title, p.symbol, id: "studio.rail.\(p.rawValue)", selected: panel == p) {
                    panel = panel == p ? nil : p
                }
            }
            railButton("Photo", "camera.fill", id: "studio.rail.photo", selected: photoMode) {
                panel = nil; photoMode = true
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 10)
        .foregroundStyle(environment.isDark ? .white : .primary)
        .modulaGlass(in: Capsule(), interactive: false,
                     tint: environment.isDark ? Color.black.opacity(0.22) : Color.primary.opacity(0.04), specular: true)
        .padding(.horizontal, 28).padding(.bottom, 28)
    }

    private func railButton(_ title: String, _ symbol: String, id: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.body.weight(.semibold))
                Text(title).font(.caption2.weight(.semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(selected ? teal : .primary)
            .background(selected ? teal.opacity(0.14) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var photoChrome: some View {
        VStack {
            HStack {
                Button { photoMode = false } label: {
                    Image(systemName: "xmark").font(.headline)
                        .foregroundStyle(environment.isDark ? .white : .black)
                        .frame(width: 44, height: 44)
                }
                .modulaGlass(in: Circle(), interactive: true, specular: true)
                .accessibilityLabel("Close photo mode")
                .accessibilityIdentifier("studio.photo.close")
                Spacer()
                Button("Done") { photoMode = false }
                    .buttonStyle(.borderedProminent)
                    .tint(teal)
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
        return p == .style || p == .wardrobe || p == .faces
    }

    /// Compact detents for Expressions & Play (~28% height), Medium for Style/Wardrobe, and capped 76% Expanded
    /// so the active 3D Moliboo remains visible above the sheet at every detent.
    private static let sheetDetents: Set<PresentationDetent> = [.medium, .fraction(0.72)]


    /// Per-character framing; with a sheet up the camera tilts down and pulls back so the Moliboo sits cleanly in the upper stage.
    private func frame(sheetOpen: Bool, animated: Bool) {
        guard MolibooFeatureFlags.native3DEnabled, let c = controller else { return }
        let f = MolibooFraming.for(characterID)
        c.cameraEntity.camera.fieldOfViewInDegrees = f.fov
        let shift: SIMD3<Float> = sheetOpen ? [0, -(f.eye.z * 0.25), f.eye.z * 0.18] : .zero
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
            HStack {
                Text(p.title).font(.title3.weight(.bold))
                Spacer()
                Button { panel = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.secondary, Color.primary.opacity(0.08))
                }
                .accessibilityIdentifier("studio.sheet.close")
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 8)

            sheet(for: p)
            Spacer(minLength: 0)
        }
        .presentationDetents(Self.sheetDetents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationDragIndicator(.visible)
        .presentationBackground {
            ZStack {
                Rectangle().fill(.regularMaterial)
                Color(uiColor: .systemBackground).opacity(0.55)
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder private func sheet(for p: Panel) -> some View {
        switch p {
        case .style: styleSheet
        case .wardrobe:
            if let session {
                if let controller {
                    MolibooWardrobeSheet(controller: controller, session: session)
                } else {
                    MolibooWardrobeSheet2D(session: session)
                }
            }
        case .faces:
            facesSheet
        }
    }

    /// Faces = expressions + a short Play row. One sheet instead of two crowded rails.
    private var facesSheet: some View {
        VStack(alignment: .leading, spacing: 22) {
            expressionsSheet
            playSheet
        }
        .padding(.bottom, 28)
    }

    private var playSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Play with \(descriptor?.displayName ?? "Moliboo")").font(.subheadline.weight(.bold))
                Spacer()
                Text(director?.napping == true ? "Napping · Tap stage to wake" : "Tap an action to react")
                    .font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(MolibooPlay.allCases) { play in
                    let active = director?.lastReaction == play.rawValue
                    Button {
                        director?.request(play.reaction)
                        pulseTick += 1
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: play.symbol).font(.subheadline.weight(.bold))
                            Text(play.title).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity, minHeight: 42)
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: Capsule(), interactive: true, tint: active ? teal : teal.opacity(0.22), prominent: active)
                    .accessibilityIdentifier("studio.play.\(play.rawValue)")
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, 24).padding(.top, 8)
    }

    private func expressionSymbol(_ e: MolibooExpression) -> String {
        switch e {
        case .idle: "face.smiling"
        case .blink: "eye.slash.fill"
        case .happy: "heart.circle.fill"
        case .excited: "sparkles"
        case .surprised: "exclamationmark.circle.fill"
        case .sleepy: "moon.zzz.fill"
        case .sad: "cloud.drizzle.fill"
        }
    }

    private var expressionsSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Expressions").font(.subheadline.weight(.bold))
                Spacer()
                Text("Active: \(controller?.expression.title ?? "Idle")")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(MolibooExpression.allCases, id: \.self) { e in
                    let selected = controller?.expression == e && e != .blink
                    Button {
                        if e == .blink { controller?.blink() } else { controller?.setExpression(e) }
                        pulseTick += 1
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: expressionSymbol(e)).font(.subheadline.weight(.bold))
                            Text(e.title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selected ? .white : .primary)
                    .modulaGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true,
                                 tint: selected ? teal : Color.primary.opacity(0.06), prominent: selected)
                    .accessibilityIdentifier("studio.expr.\(e.rawValue)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, 24).padding(.top, 8)
    }

    @ViewBuilder private var styleSheet: some View {
        MolibooStyleSheet(controller: controller, environment: $envRaw) { session?.resync() }
    }

    // MARK: Setup

    private func setUp() async {
        guard session == nil else { return }
        let ws = MolibooWardrobeSession(store: wardrobe)
        session = ws
        // 2D-only (shipping path): no RealityKit. Wardrobe/Style/Faces work without a 3D descriptor.
        if !MolibooFeatureFlags.native3DEnabled {
            if let m = MolibooRegistry.manifest, let d = MolibooRegistry.descriptor(for: characterID, manifest: m) {
                let c = MolibooSceneController(descriptor: d)
                c.cosmetics = m.cosmetics
                controller = c  // expression state only
            }
            openInitial()
            return
        }
        guard let m = MolibooRegistry.manifest, let d = MolibooRegistry.descriptor(for: characterID, manifest: m) else {
            unavailable = true; openInitial(); return
        }
        let c = MolibooSceneController(descriptor: d)
        c.cosmetics = m.cosmetics
        controller = c
        frame(sheetOpen: false, animated: false)
        await load3D(c, d, ws)
    }

    private func openInitial() {
        if startInPhoto {
            photoMode = true
        } else if let initialPanel {
            detent = .medium
            panel = initialPanel
        }
        #if DEBUG
        switch MOL03DebugHarness.panel {
        case "photo": photoMode = true
        case let p?:
            if let target = Panel(rawValue: p) {
                detent = .medium
                panel = target
            }
        case nil: break
        }
        #endif
    }

    private func load3D(_ c: MolibooSceneController, _ d: MolibooCharacterDescriptor, _ ws: MolibooWardrobeSession) async {
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
        if startInPhoto {
            photoMode = true
        } else if let initialPanel {
            detent = .medium
            panel = initialPanel
        }
        #if DEBUG
        if let clip = MOL03DebugHarness.arg("-MOL03Clip") { await measureClip(clip, controller: c, director: dir) }
        switch MOL03DebugHarness.panel {
        case "photo": photoMode = true
        case let p?:
            if let target = Panel(rawValue: p) {
                detent = .medium
                panel = target
            }
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
