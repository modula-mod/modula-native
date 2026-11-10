import SwiftUI
import UIKit

/// MOL-03 Living World: the Moliboo home. Sits inside Modula's real navigation (Settings → Moliboo / modula://moliboo);
/// its own floating nav is a section switcher, not a second tab bar. Character data comes from the shared registry,
/// selection is the existing mascot kind key, care state is `MolibooCareStore`, Studio/Wardrobe are the Living Studio.
struct MolibooWorldView: View {
    enum Section: String, CaseIterable, Identifiable {
        // Home · Studio · Stickers. Wardrobe lives inside Studio; Care is Activities on Home.
        case home, studio, stickers
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var symbol: String {
            switch self {
            case .home: "house"
            case .studio: "paintbrush.pointed"
            case .stickers: "face.smiling"
            }
        }
        var selectedSymbol: String {
            switch self {
            case .home: "house.fill"
            case .studio: "paintbrush.pointed.fill"
            case .stickers: "face.smiling.inverse"
            }
        }
        var accessibilityHint: String {
            switch self {
            case .home: "Your Moliboo's home"
            case .studio: "Opens the Studio and wardrobe"
            case .stickers: "Opens stickers"
            }
        }
    }
    enum Route: Hashable { case studio(String), photo(String), collection, cards, settings, classicStudio(MascotStudioView.StudioTab) }

    @Environment(AppEnvironment.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    @AppStorage("moliboo.world.navCollapsed") private var navCollapsed = true
    @AppStorage("moliboo.studio.forceReduceMotion") private var forceReduceMotion = false
    @State private var care = MolibooCareStore.shared
    @State private var chat: MolibooChatModel?
    @State private var stage = MolibooStageState()
    @State private var route: Route?
    @State private var showSwitcher = false
    @State private var showCareSheet = false
    @State private var sheet: Section?
    @State private var scrollY: CGFloat = 0
    /// Global bottom of the pinned header and top of the inline family tabs: once the tabs reach the
    /// header they stick under it (like a pinned section header) instead of fading out beneath it.
    @State private var headerBottom: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    @State private var inlineTabsTop: CGFloat = .greatestFiniteMagnitude
    private var tabsPinned: Bool { shows("collection") && inlineTabsTop < headerBottom + 4 }
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var toast: String?
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @FocusState private var composerFocused: Bool
    @State private var didApplyDebugKind = false
    @State private var rippleTick = 0
    @State private var joyPulseTick = 0
    @AppStorage(MolibooSettings.onboardedKey) private var onboarded = false
    @State private var showWelcome = false
    @Namespace private var heroNS
    @Namespace private var zoomNS
    @Namespace private var glassNS
    @State private var speech: String?
    @State private var speechToken = UUID()
    /// Segment shown as selected in the Home · Studio · Stickers switcher. Studio / Stickers open their own
    /// screens, so the capsule glides there first and glides back to Home when they close.
    @State private var navSelection: Section = .home
    @Namespace private var navNS
    /// Family page shown in "Choose your Moliboo" (tab strip and pager share it).
    @State private var pickerFamily: MolibooFamily?
    @Namespace private var familyTabNS
    #if DEBUG
    @AppStorage("moliboo.world.debugHour") private var debugHour = -1
    #endif

    private var characterID: String { kindRaw }
    private var kind: ModulaMascotKind? { ModulaMascotKind(rawValue: kindRaw) }
    private var displayName: String { MolibooRegistry.descriptor(for: characterID)?.displayName ?? kind?.name ?? "Moliboo" }
    private var careState: MolibooCareState { care.state(for: characterID) }
    /// Shelf figurines: other registered characters only.
    private var figurineIDs: [String] { MolibooRegistry.available3D.map(\.id).filter { $0 != characterID } }
    private let teal = Color(red: 0.22, green: 0.80, blue: 0.82)
    private var reduceMotion: Bool { systemReduceMotion || forceReduceMotion }
    /// Animation runs only while foreground, not in Low Power Mode, not under Reduced Motion.
    private var motionAllowed: Bool { scenePhase == .active && !lowPower && !reduceMotion }
    private var period: MolibooTimeOfDay {
        #if DEBUG
        if (0..<24).contains(debugHour) { return MolibooTimeOfDay.at(Calendar.current.date(bySettingHour: debugHour, minute: 0, second: 0, of: Date()) ?? Date()) }
        #endif
        return MolibooTimeOfDay.at(Date())
    }
    private var emotion: MolibooEmotion {
        if case .awaiting = chat?.phase { return .thinking }
        if case .submitting = chat?.phase { return .excited }
        if let e = stage.transient { return e }
        if chat?.isTyping == true { return .curious }
        return careState.emotion
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            LinearGradient(
                colors: [
                    Color(uiColor: .systemBackground),
                    Color(uiColor: .secondarySystemBackground).opacity(0.45),
                    Color(uiColor: .systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            // Scene art is drawn inside a fixed-size, clipped box: a bare `scaledToFill()` image widened the
            // whole ZStack past the screen, clipping every Moliboo page off the left/right edges.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .overlay(alignment: .top) { ShellSceneImage(scene: .misty).scaledToFill() }
                .clipped()
                .mask(
                    LinearGradient(colors: [.white, .white.opacity(0.92), .clear], startPoint: .top, endPoint: .bottom)
                )
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            ScrollView {
                VStack(spacing: 32) {
                    if shows("stage") {
                        navBar.padding(.top, 6)
                        stageArea.padding(.top, 12)
                    }
                    if shows("identity") || shows("stage") { heroDashboardCard }
                    if shows("activities") { careSections }
                    if shows("collection") { collection.padding(.top, 12).padding(.horizontal, -24) }
                }
                .padding(.horizontal, 24).padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
            .scrollPosition($scrollPosition)
            // Clear the floating tab bar so Activities / Choose your Moliboo never clip under it.
            .contentMargins(.bottom, 36, for: .scrollContent)
            // Nothing scrolls under the clock: content fades out beneath a scene-coloured status-bar scrim.
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in if route == nil, abs(y - scrollY) >= 8 { scrollY = y } }
            .modifier(MolibooSoftTopEdge())
            // Sticky chat bar: pinned above the safe area / keyboard (safeAreaInset follows the keyboard), over a
            // progressive bottom blur; the inset also pads the scroll content so nothing hides beneath it.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if shows("composer") {
                    composer
                        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
                        .background(alignment: .bottom) { MolibooProgressiveHeaderBlur(edge: .bottom) }
                }
            }
            // Header (back · moliboos title · sparkle · more) is pinned below the safe area (never under
            // the Dynamic Island) and stays put while content scrolls, over a progressive blur strip.
            .safeAreaInset(edge: .top, spacing: 8) {
                if shows("header") {
                    header
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { headerBottom = $0.maxY; headerHeight = $0.height }
                        .background(alignment: .top) {
                            MolibooProgressiveHeaderBlur()
                                .opacity(min(1, max(0, (scrollY - 8) / 28)))
                        }
                        .overlay(alignment: .top) {
                            if tabsPinned {
                                // Sticky family tabs just below the header. Overlay = layout-neutral, so the scroll
                                // content never jumps when they pin / unpin.
                                familyTabs
                                    .fixedSize(horizontal: false, vertical: true)
                                    .offset(y: headerHeight)
                                    .transition(.opacity)
                                    .accessibilityIdentifier("world.family.tabs.pinned")
                            }
                        }
                }
            }
            if let toast { toastView(toast) }
            if showWelcome {
                // First visit: the welcome lives over the World; "Let's go" morphs its hero onto the pedestal.
                MolibooWelcomeSheet(done: { onboarded = true; showWelcome = false }, heroNS: heroNS)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { if !onboarded { showWelcome = true } }
        .navigationDestination(item: $route) { r in destination(r) }
        .sheet(isPresented: $showSwitcher) { switcher.presentationDetents([.medium]) }
        .sheet(item: $sheet) { s in sectionSheet(s).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showCareSheet) {
            MolibooCareSheet(characterID: characterID, name: displayName, care: care) { a in
                if a == .photo { showCareSheet = false }
                performAction(a)
            }
                .presentationDetents([.medium, .large])
        }
        .task {
            #if DEBUG
            if let k = MOL03DebugHarness.arg("-MOLWorldKind"), !didApplyDebugKind { didApplyDebugKind = true; kindRaw = k }
            if let f = MOL03DebugHarness.arg("-MOLWorldFamily").flatMap(MolibooFamily.init(rawValue:)) { pickerFamily = f }
            if let y = MOL03DebugHarness.arg("-MOLWorldScrollY").flatMap(Double.init) {
                Task { try? await Task.sleep(for: .seconds(1.5)); scrollPosition.scrollTo(y: y) }
            }
            if MOL03DebugHarness.arg("-MOLWorldPush") == "studio", route == nil { try? await Task.sleep(for: .seconds(2)); route = .studio(characterID) }
            #endif
            if chat == nil { chat = MolibooChatModel(backend: MolibooIntelligenceChatBackend(service: app.intelligence)) }
            care.refresh(characterID)
            stage.wake(allowed: motionAllowed, for: MolibooStageState.launchWakeSeconds)   // brief hello, then settle
            stage.startAmbient { motionAllowed && route == nil && sheet == nil }
            // Prefetch static roster thumbs so family grids never ImageRenderer mid-scroll.
            let ids = MolibooFamily.allCases.filter { !$0.isDraft }.flatMap { $0.kinds.map(\.rawValue) }
            Task(priority: .utility) { MolibooPortrait.warmThumbs(ids: ids) }
        }
        .onChange(of: scenePhase) { _, p in
            if p == .active { care.refresh(characterID); stage.wake(allowed: motionAllowed, for: MolibooStageState.launchWakeSeconds) } else { stage.sleepNow() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onChange(of: kindRaw) { _, _ in care.refresh(characterID); stage.react(.happy, allowed: motionAllowed) }
        .onChange(of: chat?.draft ?? "") { _, _ in stage.poke(allowed: motionAllowed) }
        .onDisappear { stage.sleepNow(); stage.stopAmbient(); chat?.cancel() }
        #if DEBUG
        .overlay(alignment: .bottomTrailing) { probe }
        #endif
    }

    /// Neutral Liquid Glass for chrome only (top bar, segment, actions, chat).
    private var glassTint: Color { Color.primary.opacity(0.04) }

    private func shows(_ s: String) -> Bool {
        #if DEBUG
        return !(MOL03DebugHarness.arg("-MOLWorldHide")?.split(separator: ",").contains(Substring(s)) ?? false)
        #else
        return true
        #endif
    }

    // MARK: Header

    private var header: some View {
        ModulaGlassGroup(spacing: 10) {
            ZStack {
                // 28 pt keeps the centred logo clear of the 44 pt back / sparkle / more buttons on every iPhone width.
                MoliboosWordmark(height: 28)
                    .accessibilityIdentifier("world.logo")
                HStack(spacing: 10) {
                    MolibooWorldBackButton()
                    Spacer()
                    Button { surprise() } label: {
                        Image(systemName: "sparkles").font(.headline).frame(width: 44, height: 44)
                            .modulaGlass(in: Circle(), interactive: true, specular: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("world.sparkle").accessibilityLabel("Surprise")
                    Menu {
                        Button { route = .settings } label: { Label("Moliboo settings", systemImage: "gearshape") }
                        Button { route = .collection } label: { Label("Collection", systemImage: "square.grid.2x2") }
                        if MolibooCardFlags.enabled {
                            Button { route = .cards } label: { Label("Trading Cards", systemImage: "rectangle.portrait.on.rectangle.portrait.angled") }
                        }
                        Button { showSwitcher = true } label: { Label("Switch Moliboo", systemImage: "arrow.left.arrow.right") }
                    } label: {
                        Image(systemName: "ellipsis").font(.headline).frame(width: 44, height: 44)
                            .modulaGlass(in: Circle(), interactive: true, specular: true)
                    }
                    .accessibilityIdentifier("world.more").accessibilityLabel("More")
                }
            }
        }
        .foregroundStyle(.primary)
        .padding(.top, 4)
    }

    private func surprise() {
        let pick: MolibooEmotion = [.happy, .excited, .curious].randomElement() ?? .happy
        joyPulseTick += 1
        stage.bounce(allowed: motionAllowed); stage.react(pick, allowed: motionAllowed)
        care.interact(characterID, mood: 1, bond: 1)
    }

    // MARK: Stage

    /// Extra drawing room around the stage pet for the tap wave effects.
    private static let waveRoom: CGFloat = 72

    private var stageArea: some View {
        // Large unclipped pet + soft contact shadow. No platform glow, arches, or clip masks.
        Color.clear.frame(maxWidth: .infinity).frame(height: 292)
            .overlay {
                ZStack {
                    Ellipse()
                        .fill(Color.primary.opacity(0.10))
                        .frame(width: 140, height: 26)
                        .blur(radius: reduceMotion ? 0 : 8)
                        .offset(y: 108)
                        .allowsHitTesting(false)
                    MolibooStageCharacter(characterID: characterID, emotion: emotion, stage: stage, animating: motionAllowed && scrollY < 90,
                                          gaze: chat?.isTyping == true ? 1 : 0)
                        .frame(width: 248, height: 248)
                        // Room for the tap ripple / joy wave: the effects only draw inside the view's
                        // bounds, so they ran into the 248pt square's edges. Pad, apply, un-pad.
                        .padding(Self.waveRoom)
                        .molibooRipple(trigger: rippleTick, origin: CGPoint(x: 124 + Self.waveRoom, y: 130 + Self.waveRoom))
                        .molibooJoyPulse(trigger: joyPulseTick, tint: kind?.palette.accent ?? teal)
                        .padding(-Self.waveRoom)
                        .opacity(showWelcome ? 0 : 1)
                        .modifier(MolibooHeroMorph(ns: showWelcome ? nil : heroNS))
                        .id(characterID)
                        .transition(.opacity)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { composerFocused = true; stage.react(.curious, allowed: motionAllowed) }
                        .onTapGesture { rippleTick += 1; joyPulseTick += 1; stage.bounce(allowed: motionAllowed); care.interact(characterID, mood: 1, bond: 1); say(emotion.speech) }
                        .onLongPressGesture(minimumDuration: 0.5) { showSwitcher = true }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(displayName), \(emotion.label)")
                        .accessibilityHint("Tap to bounce, double-tap to chat, hold to switch Moliboo")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("world.stage")
                        .matchedTransitionSource(id: "world.hero", in: zoomNS)
                    if let speech {
                        Text(speech)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .modulaGlass(in: Capsule(), interactive: false)
                            .offset(y: -150)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
                            .allowsHitTesting(false)
                            .accessibilityIdentifier("world.speech")
                    }
                }
            }
            .padding(.vertical, 16)
    }

    /// Home · Studio · Stickers — Wardrobe is inside Studio; Care is Activities on Home.
    /// Native Liquid Glass segmented switcher: icon + short label, one glass capsule track the same 44 pt height as
    /// the header buttons, and a selection capsule that glides between segments (no motion under Reduce Motion).
    private var navBar: some View {
        ModulaGlassGroup(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(Section.allCases) { s in
                    let selected = navSelection == s
                    Button { select(s) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: selected ? s.selectedSymbol : s.symbol)
                                .font(.footnote.weight(.semibold))
                                .frame(width: 18)
                            Text(s.title)
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Color.primary.opacity(0.09))
                                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
                                    .matchedGeometryEffect(id: "world.nav.selection", in: navNS)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("world.nav.\(s.rawValue)")
                    .accessibilityLabel(s.title)
                    .accessibilityHint(s.accessibilityHint)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(4)
            .frame(height: 44)
            .modulaGlass(in: Capsule(), interactive: false, tint: glassTint, specular: true)
            .modulaGlassID("world.nav", in: glassNS)
        }
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Moliboo sections")
        .onChange(of: route) { _, r in if r == nil { settleNav() } }
        .onChange(of: sheet) { _, s in if s == nil { settleNav() } }
    }

    private var navAnimation: Animation? { reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82) }

    /// Glide the capsule to the tapped segment, then open it (immediately under Reduce Motion).
    private func select(_ s: Section) {
        guard s != .home else { withAnimation(navAnimation) { navSelection = .home }; return }
        withAnimation(navAnimation) { navSelection = s }
        let delay: Duration = reduceMotion ? .zero : .milliseconds(180)
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            open(s)
        }
    }

    private func settleNav() {
        guard navSelection != .home else { return }
        withAnimation(navAnimation) { navSelection = .home }
    }

    /// Open typography on the clean surface — no glass card under the pet.
    private var heroDashboardCard: some View {
        // The selected character's own catalogue number. 2D-only characters have no 3D descriptor,
        // and the old fallback (index in the Originals list, else 0 → "#001") pinned them all to #001.
        let canonNum: Int? = kind?.number
            ?? MolibooRegistry.descriptor(for: characterID)?.canonicalNumber
            ?? MolibooCosmetics.originals.firstIndex(of: characterID).map { $0 + 1 }
        let familyName = (kind?.family.displayTitle ?? "The Originals").uppercased()
        return VStack(alignment: .center, spacing: 16) {
            if shows("identity") {
                VStack(alignment: .center, spacing: 10) {
                    Text(canonNum.map { String(format: "#%03d  ·  %@", $0, familyName) } ?? familyName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .accessibilityIdentifier("world.identity.caption")
                    Text(displayName)
                        .font(.largeTitle.weight(.bold))
                        .accessibilityIdentifier("world.identity.name")
                    Text(kind?.personality ?? "A brand new Moliboo friend.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                    HStack(spacing: 12) {
                        ForEach(traits, id: \.1) { t in
                            Text(t.1)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(Color.primary.opacity(0.05), in: Capsule())
                        }
                    }
                    .padding(.top, 4)
                    .accessibilityIdentifier("world.identity.traits")
                }
            }
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var compactHeader: some View {
        HStack(spacing: 10) {
            if let img = MolibooPortrait.image(for: characterID) {
                Image(uiImage: img).resizable().interpolation(.high).scaledToFit().frame(width: 34, height: 34)
            }
            Text(displayName).font(.headline)
            Spacer()
            Label("\(Int(careState.mood))%", systemImage: "heart.fill").font(.caption.weight(.bold)).labelStyle(.titleAndIcon)
            Label("Lv. \(careState.bondLevel)", systemImage: "star.fill").font(.caption.weight(.bold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14).frame(height: 52)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityIdentifier("world.compactHeader")
    }

    // MARK: Identity

    private var traits: [(String, String, Color)] {
        let mood = MolibooRegistry.descriptor(for: characterID).map { MolibooIdlePersonality.for($0).mood.capitalized } ?? "Gentle"
        return [("leaf.fill", mood, .green), (emotion.symbol, emotion.label, .pink), ("star.fill", "Always with you", .yellow)]
    }

    // MARK: Composer

    @ViewBuilder private var composer: some View {
        if let chat {
            VStack(alignment: .leading, spacing: 8) {
                if chat.phase != .composing { chatStatus(chat) }
                ModulaGlassGroup(spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(
                                Circle().fill(LinearGradient(colors: [teal, teal.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            )
                            .modulaGlass(in: Circle(), interactive: false, tint: teal.opacity(0.35), specular: true)
                        TextField("", text: Binding(get: { chat.draft }, set: { chat.draft = $0; if chat.phase != .composing && !$0.isEmpty { chat.reset() } }))
                            .font(.body)
                            // Higher-contrast placeholder than the system default over the scene.
                            .background(alignment: .leading) {
                                if chat.draft.isEmpty {
                                    Text("Chat with \(displayName)…")
                                        .foregroundStyle(Color.secondary)
                                        .allowsHitTesting(false)
                                }
                            }
                            .focused($composerFocused)
                            .submitLabel(.send)
                            .onSubmit { send() }
                            .accessibilityIdentifier("world.composer.field")
                        Button { chat.draft += emotion.emoji } label: {
                            Image(systemName: "face.smiling")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, height: 34)
                                .modulaGlass(in: Circle(), interactive: true, specular: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("world.composer.attach").accessibilityLabel("Add \(displayName)'s mood emoji")
                        ModulaGlassSendButton(
                            ready: chat.canSend,
                            busy: chat.phase == .submitting || chat.phase == .awaiting,
                            size: 40,
                            tint: teal
                        ) { send() }
                        .accessibilityIdentifier("world.composer.send")
                    }
                    .padding(8)
                    .foregroundStyle(.primary)
                    .modulaGlass(in: Capsule(), interactive: false, tint: glassTint, specular: false)
                }
            }
        }
    }

    @ViewBuilder private func chatStatus(_ chat: MolibooChatModel) -> some View {
        Group {
            switch chat.phase {
            case .composing: EmptyView()
            case .submitting: Label("Sending…", systemImage: "paperplane")
            case .awaiting: Label("\(displayName) is thinking…", systemImage: "ellipsis.bubble")
            case .done(let reply, _): Text(reply).font(.subheadline)
            case .failed(let msg):
                HStack { Label(msg, systemImage: "exclamationmark.triangle"); Spacer(); Button("Retry") { chat.draft = chat.lastSent; send() }.accessibilityIdentifier("world.composer.retry") }
            case .unavailable(let msg): Label("Chat unavailable: \(msg)", systemImage: "bubble.left.and.exclamationmark.bubble.right")
            }
        }
        .font(.footnote)
        .padding(.horizontal, 12).padding(.vertical, chat.phase == .composing ? 0 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 16), interactive: false)
        .opacity(chat.phase == .composing ? 0 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("world.chat.status")
    }

    private func send() {
        chat?.send(as: displayName) { stage.react(.excited, allowed: motionAllowed) }
        composerFocused = false
    }

    // MARK: Care (status · activities · moments)

    private var careSections: some View {
        let life = care.life(for: characterID)
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("How \(displayName) is doing").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                // The single entry point to the Care sheet (details + full moments log).
                Button { showCareSheet = true } label: {
                    Label("Care", systemImage: "chevron.right").labelStyle(.titleOnly).font(.footnote.weight(.semibold))
                }
                .accessibilityIdentifier("world.care.open").accessibilityHint("Opens Care details")
            }
            MolibooStatusPanel(state: careState, life: life) { checkIn() }
            Text("Activities").font(.headline).padding(.top, 8).accessibilityAddTraits(.isHeader)
            MolibooActionGrid(life: life, asleep: careState.asleep, columns: 4) { performAction($0) }
            Text("Recent moments").font(.headline).padding(.top, 8).accessibilityAddTraits(.isHeader)
            MolibooMomentsList(moments: life.moments)
        }
    }

    /// Runs a care action through the shared store and shows the pet's reaction (pose, pulse, speech, haptic).
    private func performAction(_ a: MolibooCareAction) {
        switch care.perform(a, for: characterID, name: displayName) {
        case .done(let line):
            UIImpactFeedbackGenerator(style: a == .dance || a == .play ? .medium : .soft).impactOccurred()
            joyPulseTick += 1
            if a == .play || a == .dance || a == .feed { stage.bounce(allowed: motionAllowed) }
            stage.react(a == .nap ? (careState.asleep ? .sleepy : .happy) : a.reaction, allowed: motionAllowed)
            say(line)
            if a == .photo { openStudio(.photo(characterID)) }
        case .blocked(let why):
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            flash(why)
        }
    }

    private func checkIn() {
        if care.checkIn(characterID, name: displayName) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            joyPulseTick += 1
            stage.react(.happy, allowed: motionAllowed)
            say("You came back! Day \(care.life(for: characterID).streak)")
        }
    }

    /// Mood-reactive speech bubble over the pet for a couple of seconds.
    private func say(_ line: String) {
        let token = UUID()
        speechToken = token
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) { speech = line }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            guard speechToken == token else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { speech = nil }
        }
    }

    // MARK: Collection

    /// Families with members, read from data (new families such as Legends appear automatically).
    private var pickerFamilies: [MolibooFamily] { MolibooFamily.allCases.filter { !$0.isDraft && !$0.kinds.isEmpty } }
    private var currentPickerFamily: MolibooFamily { pickerFamily ?? kind?.family ?? pickerFamilies.first ?? .originals }

    private static let pickerColumns = 4
    private static let pickerTileHeight: CGFloat = 112
    private static let pickerSpacing: CGFloat = 10
    private static let pickerPageHeader: CGFloat = 64

    private func pickerPageHeight(_ f: MolibooFamily) -> CGFloat {
        let rows = CGFloat((f.kinds.count + Self.pickerColumns - 1) / Self.pickerColumns)
        return Self.pickerPageHeader + rows * Self.pickerTileHeight + max(0, rows - 1) * Self.pickerSpacing + 8
    }

    private var collection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // "See all" was a duplicate of More → Collection, so the picker title stands alone.
            Text("Choose your Moliboo").font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 24)
            familyTabs
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { inlineTabsTop = $0 }
                .opacity(tabsPinned ? 0 : 1)
                .accessibilityHidden(tabsPinned)
            familyPages
        }
        .onAppear { if pickerFamily == nil { pickerFamily = kind?.family ?? pickerFamilies.first } }
    }

    /// Liquid Glass family tab strip, kept in sync with the pager below.
    private var familyTabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                // Each family is its own glass chip (the old single capsule read as clipped at the screen edge).
                ModulaGlassGroup(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(pickerFamilies) { f in
                            let selected = f == currentPickerFamily
                            Button {
                                withAnimation(navAnimation) { pickerFamily = f }
                                UISelectionFeedbackGenerator().selectionChanged()
                            } label: {
                                Text(f.displayTitle)
                                    .font(.system(.subheadline, design: .rounded, weight: .heavy))
                                    .lineLimit(1).fixedSize()
                                    .foregroundStyle(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
                                    .padding(.horizontal, 16)
                                    .frame(height: 38)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .modulaGlass(in: Capsule(), interactive: true,
                                         tint: selected ? app.appearance.liveAccent : glassTint, prominent: selected, specular: true)
                            .id(f)
                            .accessibilityIdentifier("world.family.tab.\(f.rawValue)")
                            .accessibilityLabel(f.displayTitle)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 24, for: .scrollContent)
            .modulaHorizontalEdgeFade()
            .onChange(of: currentPickerFamily) { _, f in
                withAnimation(navAnimation) { proxy.scrollTo(f, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(currentPickerFamily, anchor: .center) }
        }
    }

    /// One page per family, paged horizontally. Height follows the visible page so short families leave no gap.
    private var familyPages: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 0) {
                ForEach(pickerFamilies) { f in
                    familyPage(f)
                        .padding(.horizontal, 24)
                        .containerRelativeFrame(.horizontal)
                        .id(f)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: Binding(get: { Optional(currentPickerFamily) }, set: { if let f = $0 { withAnimation(navAnimation) { pickerFamily = f } } }))
        .frame(height: pickerPageHeight(currentPickerFamily), alignment: .top)
        .animation(navAnimation, value: currentPickerFamily)
        .accessibilityIdentifier("world.family.pages")
    }

    private func familyPage(_ f: MolibooFamily) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                MolibooFamilyTitle(text: f.displayTitle)
                // Region under the title; skip it when it just repeats the title (The Underground).
                let numbers = String(format: "#%03d–%03d", f.range.lowerBound, f.range.upperBound)
                Text(f.world == f.displayTitle ? numbers : "\(f.world) · \(numbers)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(height: Self.pickerPageHeader - 12, alignment: .bottomLeading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            // Tiles are static UIImage thumbs, never live figures (scroll performance).
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.pickerSpacing), count: Self.pickerColumns),
                      spacing: Self.pickerSpacing) {
                ForEach(f.kinds.map(\.rawValue), id: \.self) { id in collectionTile(id) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("world.family.page.\(f.rawValue)")
    }

    private func collectionTile(_ id: String) -> some View {
        let selected = id == characterID
        let kind = ModulaMascotKind(rawValue: id)
        let num = kind?.number ?? MolibooRegistry.descriptor(for: id)?.canonicalNumber ?? 0
        let premium = kind?.isPremium == true
        return Button { kindRaw = id } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let img = MolibooPortrait.thumb(for: id, dressed: id == characterID) ?? MolibooPortrait.image(for: id) {
                            Image(uiImage: img).resizable().interpolation(.medium).scaledToFit()
                        } else {
                            Color(uiColor: .tertiarySystemFill)
                        }
                    }
                    .frame(width: 60, height: 60)
                    if premium {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(4)
                    }
                }
                Text(String(format: "#%03d", num))
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
                Text(kind?.name ?? id.capitalized)
                    .font(.caption.weight(.semibold)).lineLimit(1)
            }
            .padding(.vertical, 10).padding(.horizontal, 6)
            .frame(maxWidth: .infinity).frame(height: Self.pickerTileHeight)
            .foregroundStyle(.primary)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? teal.opacity(0.9) : Color.primary.opacity(0.06), lineWidth: selected ? 1.5 : 0.5)
            )
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.body).foregroundStyle(.white, teal).padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("world.collection.\(id)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func sectionTitle(_ t: String, seeAll: @escaping () -> Void) -> some View {
        HStack {
            Text(t).font(.headline)
            Spacer()
            Button("See all", action: seeAll).font(.footnote.weight(.semibold))
                .accessibilityIdentifier("world.seeall.\(t.lowercased().replacingOccurrences(of: " ", with: "-"))")
        }
        .foregroundStyle(.primary)
        // Sections bleed edge to edge (padding -24), so the title restores the page margin.
        .padding(.horizontal, 24)
    }

    // MARK: Navigation

    private func open(_ s: Section) {
        switch s {
        case .home: break
        case .studio: openStudio(.studio(characterID))  // Living Studio includes Wardrobe
        case .stickers: sheet = .stickers
        }
    }

    private func openStudio(_ r: Route) {
        guard MolibooRegistry.descriptor(for: characterID) != nil else {
            // Family 002+ Moliboos have no stage descriptor: open the full 2D Studio (wardrobe, emotes, photo).
            route = .classicStudio(.wardrobe)
            return
        }
        route = r
    }

    @ViewBuilder private func destination(_ r: Route) -> some View {
        switch r {
        case .studio(let id): MolibooLivingStudioView(characterID: id).navigationTransition(.zoom(sourceID: "world.hero", in: zoomNS))
        case .photo(let id): MolibooLivingStudioView(characterID: id, startInPhoto: true).navigationTransition(.zoom(sourceID: "world.hero", in: zoomNS))
        case .collection: MolibooCollectionView()
        case .cards: MolibooCardsHomeView()
        case .settings: MolibooSettingsView()
        case .classicStudio(let tab): MascotStudioView(initialTab: tab)
        }
    }

    @ViewBuilder private func sectionSheet(_ s: Section) -> some View {
        switch s {
        case .stickers: MolibooStickerSheet(characterID: characterID, name: displayName) { flash($0) }
        case .home, .studio: EmptyView()
        }
    }

    private var switcher: some View {
        NavigationStack {
            List(MolibooRegistry.available3D.map(\.id), id: \.self) { id in
                Button { kindRaw = id; showSwitcher = false } label: {
                    HStack {
                        if let img = MolibooPortrait.image(for: id) { Image(uiImage: img).resizable().scaledToFit().frame(width: 40, height: 40) }
                        Text(MolibooRegistry.descriptor(for: id)?.displayName ?? id)
                        Spacer()
                        if id == characterID { Image(systemName: "checkmark").foregroundStyle(.cyan) }
                    }
                }
                .accessibilityIdentifier("world.switcher.\(id)")
            }
            .navigationTitle("Switch Moliboo").navigationBarTitleDisplayMode(.inline)
        }
    }

    private func flash(_ s: String) {
        ModulaToastCenter.shared.show(s, symbol: "sparkles", tone: .info)
    }

    private func toastView(_ s: String) -> some View {
        Text(s).font(.footnote.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .frame(maxWidth: .infinity).padding(.top, 54)
            .accessibilityIdentifier("world.toast")
            .allowsHitTesting(false)
    }

    #if DEBUG
    private var probe: some View {
        let s = careState
        let v = "char=\(characterID) emotion=\(emotion.rawValue) period=\(period.rawValue) mood=\(Int(s.mood)) energy=\(Int(s.energy)) bond=\(s.bondLevel) xp=\(Int(s.bondXP)) asleep=\(s.asleep ? 1 : 0) chat=\(chat?.phase.key ?? "nil") awake=\(stage.awake ? 1 : 0) anim=\(motionAllowed && stage.awake ? 1 : 0) bounces=\(stage.bounces) nav=\(navCollapsed ? "collapsed" : "open") route=\(route.map { "\($0)" } ?? "none")"
        return Text(v).font(.system(size: 1)).opacity(0.01).frame(width: 1, height: 1)
            .accessibilityIdentifier("world.state").accessibilityLabel(v)
    }
    #endif
}

/// Short-lived stage reactions + idle settling. The stage is "awake" (animating) for a while after any
/// interaction, then settles: no continuous redraw while idle.
@MainActor
@Observable
final class MolibooStageState {
    /// Brief hello on appear/foreground. UI tests pass -MOLWorldNoLaunchWake so XCTest snapshots never race the wake animation.
    static var launchWakeSeconds: Double {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-MOLWorldNoLaunchWake") { return 0 }
        #endif
        return min(3, awakeSeconds)
    }

    private(set) var awake = false
    private(set) var transient: MolibooEmotion?
    private(set) var bounceToken = 0
    private(set) var bounces = 0
    private(set) var blinkToken = 0
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var blinkTask: Task<Void, Never>?
    @ObservationIgnored private var transientTask: Task<Void, Never>?
    /// How long the stage keeps animating after the last interaction (test hook: `moliboo.world.awakeSeconds`).
    static var awakeSeconds: Double {
        let v = UserDefaults.standard.double(forKey: "moliboo.world.awakeSeconds")
        return v > 0 ? v : 10
    }

    func wake(allowed: Bool, for seconds: Double? = nil) {
        guard allowed else { sleepNow(); return }
        awake = true
        settleTask?.cancel()
        let span = seconds ?? Self.awakeSeconds
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(span))
            guard !Task.isCancelled else { return }
            self?.awake = false
        }
        scheduleBlinks()
    }

    func poke(allowed: Bool) { if allowed { wake(allowed: true) } }

    func sleepNow() {
        awake = false; settleTask?.cancel(); blinkTask?.cancel(); blinkTask = nil
    }

    func bounce(allowed: Bool) {
        bounces += 1
        bounceToken += 1
        wake(allowed: allowed)
    }

    func react(_ e: MolibooEmotion, allowed: Bool, for seconds: Double = 2.5) {
        transient = e
        wake(allowed: allowed)
        transientTask?.cancel()
        transientTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.transient = nil
        }
    }

    /// Occasional ambient life while the World is on screen: every 14–28 s a short wake (≈3 s of breathing,
    /// sway and particles) with a happy/curious emote. Duty-cycled so an untouched World stays mostly still.
    @ObservationIgnored private var ambientTask: Task<Void, Never>?
    func startAmbient(allowed: @escaping @MainActor () -> Bool) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-MOLWorldNoLaunchWake") { return }
        #endif
        guard ambientTask == nil else { return }
        ambientTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 14...28)))
                guard let self, !Task.isCancelled else { break }
                guard allowed(), !self.awake else { continue }
                self.react([.happy, .curious, .excited].randomElement() ?? .happy, allowed: true, for: 2.2)
                self.wake(allowed: true, for: 3)
            }
        }
    }
    func stopAmbient() { ambientTask?.cancel(); ambientTask = nil }

    /// Irregular blinks (2.5–6 s apart) while awake. One-shot animations, not a frame loop.
    private func scheduleBlinks() {
        guard blinkTask == nil else { return }
        blinkTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 2.5...6)))
                guard let self, self.awake, !Task.isCancelled else { break }
                self.blinkToken += 1
            }
            self?.blinkTask = nil
        }
    }
}


/// Reads `dismiss` in its own tiny view: when the World itself depended on `\.dismiss`, pushing a destination
/// (Studio) made SwiftUI re-invalidate both views endlessly (100% CPU, UI-test snapshot timeouts).
private struct MolibooWorldBackButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44)
                .modulaGlass(in: Circle(), interactive: true, specular: true)
        }
        .accessibilityIdentifier("world.back").accessibilityLabel("Back")
    }
}

/// iOS 26 soft scroll edge at the top (content blurs out under the status bar); a fade mask on earlier systems.
struct MolibooSoftTopEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

extension MolibooFamily {
    /// Chip colour for the selected family tab: the family's first Moliboo's deep tone.
    var chipTint: Color { (kinds.first?.palette.dark ?? .accentColor).opacity(0.9) }
}
