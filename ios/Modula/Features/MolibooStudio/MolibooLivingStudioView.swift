import SwiftUI
import RealityKit

/// MOL-03R Living Studio: persistent 3D stage (per-character framing + environment shaders + volumetric halo),
/// crisp header, floating Liquid Glass action rail, and non-blocking sheets (Compact / Medium / 76% Expanded)
/// so the active Moliboo remains visible on stage at all times.
struct MolibooLivingStudioView: View {
    let characterID: String

    enum Panel: String, Identifiable, CaseIterable {
        case style, wardrobe, play, expressions, more
        var id: String { rawValue }
        var title: String { switch self { case .style: "Style"; case .wardrobe: "Wardrobe"; case .play: "Play"; case .expressions: "Faces"; case .more: "More" } }
        var symbol: String { switch self { case .style: "paintpalette.fill"; case .wardrobe: "tshirt.fill"; case .play: "gamecontroller.fill"; case .expressions: "face.smiling"; case .more: "sparkles.rectangle.stack" } }
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
            // Volumetric stage halo + floor glow under the active Moliboo
            Circle()
                .fill(.clear)
                .frame(width: 340, height: 340)
                .molibooStageAura(accentColor, strength: environment.isDark ? 0.75 : 0.48, animated: live)
                .offset(y: -90)
            Ellipse()
                .fill(environment.floor.opacity(0.88))
                .frame(height: 220)
                .molibooCaustics(teal.opacity(0.75), animated: live)
                .offset(y: 90)
                .blur(radius: 18)
        }
        .molibooJoyPulse(trigger: pulseTick, tint: accentColor)
        .ignoresSafeArea()
        .accessibilityIdentifier("studio.environment.\(environment.rawValue)")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(descriptor?.displayName ?? "Moliboo")
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                    if let d = descriptor {
                        Text(String(format: "#%03d", d.canonicalNumber))
                            .font(.caption2.weight(.bold).monospaced())
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                if let mood = director?.personality.mood {
                    HStack(spacing: 5) {
                        Circle().fill(teal).frame(width: 6, height: 6)
                        Text("\(mood.capitalized) companion · \(controller?.expression.title ?? "Idle")")
                            .font(.caption.weight(.semibold))
                            .opacity(0.85)
                    }
                }
            }
            .shadow(color: environment.isDark ? .black.opacity(0.45) : .white.opacity(0.7), radius: 3, y: 1)
            Spacer()
            Menu {
                // Explicit rows read the active background straight from `environment` (the same
                // value the stage renders), so the checkmark can't drift from what's on screen.
                ForEach(MolibooEnvironment.allCases) { e in
                    Button { envRaw = e.rawValue } label: {
                        if e == environment { Label(e.title, systemImage: "checkmark") } else { Label(e.title, systemImage: e.symbol) }
                    }
                    .accessibilityAddTraits(e == environment ? .isSelected : [])
                }
            } label: {
                Label(environment.title, systemImage: environment.symbol)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .modulaGlass(in: Capsule(), interactive: true, specular: true)
                    .molibooSpecularRim(0.45, animated: !reduceMotion)
            }
            .accessibilityIdentifier("studio.envMenu")
        }
        // Text follows the stage, not the app scheme (white-on-white on light stages before).
        .foregroundStyle(environment.isDark ? .white : .black)
        .environment(\.colorScheme, environment.isDark ? .dark : .light)
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
                .simultaneousGesture(TapGesture().onEnded { director?.request(.tap); pulseTick += 1 })
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in director?.request(.pet); pulseTick += 1 })
                .accessibilityIdentifier("moliboo3d.view")
                // RealityView's first frames are black: fade the stage in once it has rendered.
                .opacity(stageRevealed ? 1 : 0)
                .task {
                    try? await Task.sleep(for: .milliseconds(350))
                    withAnimation(.easeOut(duration: 0.35)) { stageRevealed = true }
                }
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
        HStack(spacing: 8) {
            ForEach(Panel.allCases) { p in
                railButton(p.title, p.symbol, id: "studio.rail.\(p.rawValue)", selected: panel == p) {
                    panel = panel == p ? nil : p
                }
            }
            railButton("Photo", "camera.fill", id: "studio.rail.photo", selected: false) { panel = nil; photoMode = true }
        }
        .padding(8)
        .foregroundStyle(environment.isDark ? .white : .primary)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous), interactive: false,
                     tint: environment.isDark ? Color.black.opacity(0.28) : Color.white.opacity(0.25), specular: true)
        .molibooSpecularRim(0.4, animated: !reduceMotion)
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        .environment(\.colorScheme, environment.isDark ? .dark : .light)
        .padding(.horizontal, 14).padding(.bottom, 20)
    }

    private func railButton(_ title: String, _ symbol: String, id: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.headline)
                Text(title).font(.caption2.weight(.bold)).lineLimit(1).minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(selected ? teal.opacity(0.35) : .clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(MolibooSpringPressStyle())
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
        return p == .style || p == .wardrobe || p == .expressions
    }

    /// Compact detents for Expressions & Play (~28% height), Medium for Style/Wardrobe, and capped 76% Expanded
    /// so the active 3D Moliboo remains visible above the sheet at every detent.
    private static let compactDetent: PresentationDetent = .height(250)
    private static let styleDetent: PresentationDetent = .height(300)
    private static let expandedDetent: PresentationDetent = .fraction(0.76)

    private static func detents(for p: Panel) -> Set<PresentationDetent> {
        switch p {
        case .expressions, .play: [compactDetent, .medium]
        case .style: [styleDetent, .medium]
        case .wardrobe, .more: [.medium, expandedDetent]
        }
    }

    private static func defaultDetent(for p: Panel) -> PresentationDetent {
        switch p {
        case .expressions, .play: compactDetent
        case .style: styleDetent
        case .wardrobe, .more: .medium
        }
    }

    /// Per-character framing; with a sheet up the camera tilts down and pulls back so the Moliboo sits cleanly in the upper stage.
    private func frame(sheetOpen: Bool, animated: Bool) {
        guard let c = controller else { return }
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
            // Single top-level segmented control inside the sheet, with a close button on the trailing edge.
            HStack(spacing: 0) {
                ForEach(Panel.allCases) { q in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            panel = q
                        }
                    } label: {
                        Text(q.title)
                            .font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, minHeight: 34)
                            .background {
                                if q == p {
                                    Capsule().fill(teal).matchedGeometryEffect(id: "studio.segment", in: segmentNS)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(q == p ? .white : .primary)
                    .accessibilityIdentifier("studio.sheet.tab.\(q.rawValue)")
                    .accessibilityAddTraits(q == p ? .isSelected : [])
                }
            }
            .padding(3)
            .modulaGlass(in: Capsule(), interactive: false)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("studio.sheet.tabs")
            .safeAreaInset(edge: .trailing) {
                Button { panel = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.primary, Color.primary.opacity(0.12))
                        .frame(width: 36, height: 36)
                }
                .accessibilityIdentifier("studio.sheet.close")
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 18).padding(.top, 26)

            sheet(for: p)
            Spacer(minLength: 0)
        }
        .presentationDetents(p == .wardrobe || p == .more ? [.medium, .fraction(0.78)] : [.height(280), .medium])
        .presentationBackgroundInteraction(.enabled(upThrough: p == .wardrobe || p == .more ? .medium : .height(280)))
        .presentationDragIndicator(.visible)
        .presentationBackground {
            // Clean glass that adapts to the stage: frosted white in light, deep blue in dark.
            ZStack {
                Rectangle().fill(environment.isDark ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(.regularMaterial))
                (environment.isDark ? Color(red: 0.10, green: 0.10, blue: 0.24).opacity(0.45) : Color.white.opacity(0.55))
            }
            .ignoresSafeArea()
        }
        .environment(\.colorScheme, environment.isDark ? .dark : .light)
    }

    @ViewBuilder private func sheet(for p: Panel) -> some View {
        switch p {
        case .style: styleSheet
        case .wardrobe:
            if let controller, let session { MolibooWardrobeSheet(controller: controller, session: session) }
        case .play: playSheet
        case .expressions: expressionsSheet
        case .more:
            ScrollView {
                MascotStudioView(initialTab: moreTab, embedded: true)
                    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 32)
            }
        }
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
                    .buttonStyle(MolibooSpringPressStyle())
                    .modulaGlass(in: Capsule(), interactive: true, tint: active ? teal : teal.opacity(0.22), prominent: active)
                    .accessibilityIdentifier("studio.play.\(play.rawValue)")
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, 18).padding(.top, 12)
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
                    .buttonStyle(MolibooSpringPressStyle())
                    .foregroundStyle(selected ? .white : .primary)
                    .modulaGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true,
                                 tint: selected ? teal : Color.primary.opacity(0.06), prominent: selected)
                    .accessibilityIdentifier("studio.expr.\(e.rawValue)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, 18).padding(.top, 12)
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
        if startInPhoto {
            photoMode = true
        } else if let initialPanel {
            detent = Self.defaultDetent(for: initialPanel)
            panel = initialPanel
        }
        #if DEBUG
        if let clip = MOL03DebugHarness.arg("-MOL03Clip") { await measureClip(clip, controller: c, director: dir) }
        switch MOL03DebugHarness.panel {
        case "photo": photoMode = true
        case let p?:
            if let target = Panel(rawValue: p) {
                detent = Self.defaultDetent(for: target)
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
