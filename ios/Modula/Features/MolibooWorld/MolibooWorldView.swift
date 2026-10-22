import SwiftUI
import UIKit

/// MOL-03 Living World: the Moliboo home. Sits inside Modula's real navigation (Settings → Moliboo / modula://moliboo);
/// its own floating nav is a section switcher, not a second tab bar. Character data comes from the shared registry,
/// selection is the existing mascot kind key, care state is `MolibooCareStore`, Studio/Wardrobe are the Living Studio.
struct MolibooWorldView: View {
    enum Section: String, CaseIterable, Identifiable {
        case home, studio, wardrobe, stickers, care
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var symbol: String {
            switch self {
            case .home: "house"; case .studio: "paintbrush.pointed"; case .wardrobe: "tshirt"
            case .stickers: "face.smiling"; case .care: "heart"
            }
        }
    }
    enum Route: Hashable { case studio(String), wardrobe(String), photo(String), collection, cards, settings }

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
    @State private var sheet: Section?
    @State private var scrollY: CGFloat = 0
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
            if shows("backdrop") { MolibooRoomBackdrop(period: period, scrollY: scrollY, animating: motionAllowed && stage.awake, figurines: figurineIDs) }
            ScrollView {
                VStack(spacing: 20) {
                    if shows("stage") { navBar; stageArea }
                    if shows("identity") || shows("stage") {
                        heroDashboardCard
                    }
                    if shows("quick") { quickActions }
                    if shows("composer") { composer }
                    if shows("activities") { activities }
                    if shows("collection") { collection }
                }
                .padding(.horizontal, 16).padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            // Clear the floating tab bar so Activities / Choose your Moliboo never clip under it.
            .contentMargins(.bottom, 110, for: .scrollContent)
            // Nothing scrolls under the clock: content fades out beneath a scene-coloured status-bar scrim.
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in if route == nil, abs(y - scrollY) >= 1 { scrollY = y } }
            .modifier(MolibooSoftTopEdge())
            // Header (back · moliboos title · sparkle · more) is pinned below the safe area (never under
            // the Dynamic Island) and stays put while content scrolls, over a progressive blur strip.
            .safeAreaInset(edge: .top, spacing: 8) {
                if shows("header") {
                    header
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                        .background(alignment: .top) {
                            MolibooProgressiveStrip()
                                .opacity(scrollY > 20 ? 1 : 0)
                                .animation(.easeOut(duration: 0.2), value: scrollY > 20)
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
        .onAppear { if !onboarded { showWelcome = true } }
        .navigationDestination(item: $route) { r in destination(r) }
        .sheet(isPresented: $showSwitcher) { switcher.presentationDetents([.medium]) }
        .sheet(item: $sheet) { s in sectionSheet(s).presentationDetents([.medium, .large]) }
        .task {
            #if DEBUG
            if let k = MOL03DebugHarness.arg("-MOLWorldKind"), !didApplyDebugKind { didApplyDebugKind = true; kindRaw = k }
            if MOL03DebugHarness.arg("-MOLWorldPush") == "studio", route == nil { try? await Task.sleep(for: .seconds(2)); route = .studio(characterID) }
            #endif
            if chat == nil { chat = MolibooChatModel(backend: MolibooIntelligenceChatBackend(service: app.intelligence)) }
            care.refresh(characterID)
            stage.wake(allowed: motionAllowed, for: MolibooStageState.launchWakeSeconds)   // brief hello, then settle
            stage.startAmbient { motionAllowed && route == nil && sheet == nil }
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

    /// Tinted Liquid Glass for panels over the scene: a cool tint at night, warm white by day, plus a soft drop shadow.
    private var glassTint: Color { period.isDark ? Color(red: 0.30, green: 0.32, blue: 0.70).opacity(0.28) : Color.white.opacity(0.22) }

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
                Image("MoliboosLogo").resizable().scaledToFit().frame(maxWidth: 200).frame(height: 50)
                    .shadow(color: .white.opacity(0.55), radius: 1, y: -1)          // glossy top edge
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 4)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "sparkle").font(.system(size: 18, weight: .bold)).foregroundStyle(.yellow)
                            .shadow(color: .yellow.opacity(0.7), radius: 6).offset(x: 10, y: -8)
                            .phaseAnimator([0.8, 1.15], trigger: stage.awake) { v, s in v.scaleEffect(motionAllowed && stage.awake ? s : 1) }
                    }
                    .accessibilityLabel("Moliboos").accessibilityIdentifier("world.logo")
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
        .foregroundStyle(period.isDark ? .white : .primary)
        .padding(.top, 4)
    }

    private func surprise() {
        let pick: MolibooEmotion = [.happy, .excited, .curious].randomElement() ?? .happy
        joyPulseTick += 1
        stage.bounce(allowed: motionAllowed); stage.react(pick, allowed: motionAllowed)
        care.interact(characterID, mood: 1, bond: 1)
    }

    // MARK: Stage

    private var stageArea: some View {
        // Character dominates the first viewport; identity card sits below as secondary chrome.
        Color.clear.frame(maxWidth: .infinity).frame(height: 328)
            .overlay {
                ZStack {
                    Circle()
                        .fill(.clear)
                        .frame(width: 310, height: 310)
                        .molibooStageAura(kind?.palette.accent ?? teal, strength: period.isDark ? 0.68 : 0.45, animated: motionAllowed && stage.awake)
                        .allowsHitTesting(false)
                    MolibooStageCharacter(characterID: characterID, emotion: emotion, stage: stage, animating: motionAllowed,
                                          gaze: chat?.isTyping == true ? 1 : 0)
                        .frame(width: 318, height: 318)
                        .molibooRipple(trigger: rippleTick, origin: CGPoint(x: 150, y: 170))
                        .molibooJoyPulse(trigger: joyPulseTick, tint: kind?.palette.accent ?? teal)
                        .opacity(showWelcome ? 0 : 1)
                        .modifier(MolibooHeroMorph(ns: showWelcome ? nil : heroNS))
                        // Picking in the carousel flies the new Moliboo up into the hero spot.
                        .id(characterID)
                        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .scale(scale: 0.35, anchor: .bottom).combined(with: .offset(y: 260)).combined(with: .opacity),
                                                                          removal: .scale(scale: 0.6).combined(with: .opacity)))
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { composerFocused = true; stage.react(.curious, allowed: motionAllowed) }
                        .onTapGesture { rippleTick += 1; joyPulseTick += 1; stage.bounce(allowed: motionAllowed); care.interact(characterID, mood: 1, bond: 1) }
                        .onLongPressGesture(minimumDuration: 0.5) { showSwitcher = true }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(displayName), \(emotion.label)")
                        .accessibilityHint("Tap to bounce, double-tap to chat, hold to switch Moliboo")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("world.stage")
                        // Studio / Wardrobe / Photo zoom out of the character itself (real morph, not a cut).
                        .matchedTransitionSource(id: "world.hero", in: zoomNS) { $0.clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous)) }
                }
            }
    }

    /// Compact section switcher — icon-first so it never reads as a second Modula tab bar.
    private var navBar: some View {
        ModulaGlassGroup(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Section.allCases) { s in
                    Button { open(s) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: s == .home ? "house.fill" : s.symbol).font(.caption.weight(.semibold))
                            if !navCollapsed { Text(s.title).font(.caption2.weight(.semibold)).lineLimit(1) }
                        }
                        .padding(.horizontal, 10).frame(minHeight: 32)
                        .background {
                            if s == .home { Capsule().fill(.white.opacity(period.isDark ? 0.20 : 0.45)).modulaGlassID("world.nav.selected", in: glassNS) }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("world.nav.\(s.rawValue)").accessibilityLabel(s.title)
                }
            }
            .padding(3)
            }
            .modulaHorizontalEdgeFade(14)
            .modulaGlass(in: Capsule(), interactive: false, tint: glassTint.opacity(0.85), specular: true)
            .modulaGlassID("world.nav", in: glassNS)
            .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
        }
        .foregroundStyle(period.isDark ? .white.opacity(0.92) : .primary)
        .padding(.bottom, 4)
    }

    /// Unified Hero Dashboard Card: combines Character Identity (Primary) + Trait Pills + Mood/Energy/Bond Meters (Secondary)
    /// into one cohesive Liquid Glass surface with specular rim and subtle holo sheen.
    private var heroDashboardCard: some View {
        let canonNum = MolibooRegistry.descriptor(for: characterID)?.canonicalNumber
            ?? ((MolibooCosmetics.originals.firstIndex(of: characterID) ?? 0) + 1)
        return VStack(spacing: 12) {
            if shows("identity") {
                VStack(spacing: 5) {
                    HStack(spacing: 6) {
                        Text(String(format: "#%03d", canonNum))
                            .font(.caption2.weight(.heavy).monospaced())
                            .foregroundStyle(teal)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(teal.opacity(0.22), in: Capsule())
                        Text("ORIGINALS")
                            .font(.caption2.weight(.bold).monospaced())
                            .tracking(1.2)
                            .foregroundStyle(period.isDark ? .white.opacity(0.72) : .secondary)
                    }
                    (Text("Hi, I'm ") + Text(displayName).foregroundStyle(teal) + Text("!"))
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .accessibilityIdentifier("world.identity.name")
                    Text(kind?.personality ?? "A brand new Moliboo friend.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(period.isDark ? .white.opacity(0.88) : .secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        ForEach(traits, id: \.1) { t in
                            HStack(spacing: 4) {
                                Image(systemName: t.0).foregroundStyle(t.2)
                                Text(t.1)
                            }
                            .font(.caption.weight(.semibold)).lineLimit(1)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(t.2.opacity(period.isDark ? 0.22 : 0.14), in: Capsule())
                            .overlay(Capsule().strokeBorder(t.2.opacity(0.35), lineWidth: 0.8))
                        }
                    }
                    .padding(.top, 2)
                    .accessibilityIdentifier("world.identity.traits")
                }
            }
            if shows("stage") {
                statsRow
            }
        }
        .foregroundStyle(period.isDark ? .white : .primary)
        .padding(.vertical, 14).padding(.horizontal, 14).frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) { Image(systemName: "sparkle").foregroundStyle(teal.opacity(0.85)).padding(14) }
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(period.isDark ? Color.black.opacity(0.42) : Color.white.opacity(0.55))
        }
        .modulaGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous), interactive: false, tint: glassTint, specular: true)
        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
        .padding(.top, -4)
    }

    /// Mood / energy / bond as three high-contrast glass meters inside the hero dashboard.
    private var statsRow: some View {
        ModulaGlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                stat("heart.fill", .pink, "\(Int(careState.mood))%", "Mood", id: "mood")
                stat("bolt.fill", .yellow, "\(Int(careState.energy))%", "Energy", id: "energy")
                stat("star.fill", .orange, "Lv. \(careState.bondLevel)", "Bond", id: "bond")
            }
        }
        .foregroundStyle(period.isDark ? .white : .primary)
        .contentTransition(.numericText())
        .animation(reduceMotion ? nil : .spring, value: careState)
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
        .foregroundStyle(period.isDark ? .white : .primary)
        .padding(.horizontal, 14).frame(height: 52)
        .molibooGlassBackground(Capsule(), tint: glassTint)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityIdentifier("world.compactHeader")
    }

    private func stat(_ symbol: String, _ tint: Color, _ value: String, _ label: String, id: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.caption.weight(.bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(tint.gradient, in: Circle())
                .shadow(color: tint.opacity(0.5), radius: 4)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.subheadline.weight(.heavy)).monospacedDigit()
                Text(label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(period.isDark ? .white.opacity(0.78) : .secondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: .infinity)
        .background(period.isDark ? Color.black.opacity(0.38) : Color.white.opacity(0.55), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(period.isDark ? 0.18 : 0.35), lineWidth: 0.8))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("world.stat.\(id)")
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
                                        .foregroundStyle(period.isDark ? Color.white.opacity(0.75) : Color.primary.opacity(0.6))
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
                    .padding(7)
                    .foregroundStyle(period.isDark ? .white : .primary)
                    .modulaGlass(in: Capsule(), interactive: false, tint: glassTint, specular: true)
                    .shadow(color: teal.opacity(period.isDark ? 0.18 : 0.08), radius: 12, y: 4)
                }
                chatStatus(chat)
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

    // MARK: Quick actions

    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                quick("Say hi", "Take a moment to say hi", "bubble.left.fill", .blue, id: "sayhi") {
                    joyPulseTick += 1
                    care.interact(characterID, mood: 3, bond: 3); stage.react(.happy, allowed: motionAllowed); flash("\(displayName) waves back!")
                }
                quick("Play", "Play together", "gamecontroller.fill", .purple, id: "play") { doActivity(.play) }
                quick("Treat", "Give a treat", "carrot.fill", .orange, id: "treat") { doActivity(.feed) }
                quick("Photo", "Take photo", "camera.fill", .cyan, id: "photo") { openStudio(.photo(characterID)) }
                if MolibooCardFlags.enabled {
                    quick("Cards", "Trading Cards", "rectangle.portrait.on.rectangle.portrait.angled.fill", .pink, id: "cards") { route = .cards }
                }
            }
            .padding(.vertical, 4)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .modulaHorizontalEdgeFade()
    }

    private func quick(_ title: String, _ a11y: String, _ symbol: String, _ tint: Color, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(title).lineLimit(1).fixedSize(horizontal: true, vertical: false)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(period.isDark ? .white : .primary)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(tint.opacity(period.isDark ? 0.22 : 0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.45), lineWidth: 1))
            .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
        }
        .buttonStyle(MolibooSpringPressStyle())
        .accessibilityIdentifier("world.quick.\(id)")
        .accessibilityLabel(a11y)
    }

    // MARK: Activities (Care)

    private var activities: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Activities") { sheet = .care }
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(MolibooActivity.allCases) { a in activityCard(a) }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .modulaHorizontalEdgeFade()
        }
    }

    private func activityCard(_ a: MolibooActivity) -> some View {
        Button { doActivity(a) } label: {
            VStack(alignment: .leading, spacing: 0) {
                MolibooActivityScene(activity: a, characterID: characterID)
                    .frame(height: 128)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a == .sleep && careState.asleep ? "Wake up" : a.title).font(.subheadline.weight(.bold))
                        Text(a.subtitle)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(period.isDark ? .white.opacity(0.78) : .secondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.9)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold)).opacity(0.6)
                }
                .padding(10)
            }
            .frame(width: 156)
            .foregroundStyle(period.isDark ? .white : .primary)
            .background(period.isDark ? Color.black.opacity(0.36) : Color.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: true, tint: glassTint, specular: true)
            .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
        }
        .buttonStyle(MolibooSpringPressStyle())
        .accessibilityIdentifier("world.activity.\(a.rawValue)")
    }

    private func doActivity(_ a: MolibooActivity) {
        let ok = care.perform(a, for: characterID)
        if ok {
            joyPulseTick += 1
            switch a {
            case .sleep: stage.react(careState.asleep ? .sleepy : .happy, allowed: motionAllowed)
            case .play: stage.bounce(allowed: motionAllowed); stage.react(.excited, allowed: motionAllowed)
            case .clean, .feed: stage.react(.happy, allowed: motionAllowed)
            }
            flash(message(after: a))
        } else {
            flash(careState.asleep ? "\(displayName) is asleep. Wake them first." : "\(displayName) is too tired. Try Sleep.")
        }
    }

    private func message(after a: MolibooActivity) -> String {
        let s = careState
        switch a {
        case .sleep: return s.asleep ? "\(displayName) is napping. Energy will refill." : "\(displayName) woke up!"
        case .play: return "Fun! Mood \(Int(s.mood))%, energy \(Int(s.energy))%."
        case .clean: return "Squeaky clean!"
        case .feed: return "Yum! Energy \(Int(s.energy))%."
        }
    }

    // MARK: Collection

    private var collection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Choose your Moliboo") { route = .settings }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(MolibooRegistry.available3D.map(\.id), id: \.self) { id in collectionTile(id) }
                }
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .modulaHorizontalEdgeFade()
        }
    }

    private func collectionTile(_ id: String) -> some View {
        let selected = id == characterID
        let num = MolibooRegistry.descriptor(for: id)?.canonicalNumber ?? ((MolibooCosmetics.originals.firstIndex(of: id) ?? 0) + 1)
        return Button { withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.6)) { kindRaw = id } } label: {
            VStack(spacing: 4) {
                if let img = MolibooPortrait.image(for: id) {
                    Image(uiImage: img).resizable().interpolation(.high).scaledToFit().frame(height: 74)
                        .molibooPortraitEdge()
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 3)
                }
                Text(String(format: "#%03d", num))
                    .font(.caption2.weight(.bold).monospaced())
                    .opacity(0.82)
                Text(MolibooRegistry.descriptor(for: id)?.displayName ?? id.capitalized).font(.caption.weight(.bold))
                if ModulaMascotKind(rawValue: id)?.isPremium == true {
                    Label("Premium", systemImage: "crown.fill").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 10).padding(.horizontal, 6).frame(width: 98)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .background {
                // Character-coloured gradient card with a soft inner glow behind the portrait.
                let pal = ModulaMascotKind(rawValue: id)?.palette
                ZStack {
                    LinearGradient(colors: [(pal?.light ?? .white).opacity(0.85), (pal?.dark ?? .indigo).opacity(0.85)], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [.white.opacity(0.55), .clear], center: UnitPoint(x: 0.5, y: 0.32), startRadius: 2, endRadius: 52)
                    if selected { Color.white.opacity(0.18).molibooHoloFoil(0.6, animated: motionAllowed) }   // holo foil behind the portrait
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(selected ? teal : .white.opacity(0.35), lineWidth: selected ? 2 : 0.8))
            .shadow(color: selected ? teal.opacity(0.75) : (ModulaMascotKind(rawValue: id)?.palette.mid ?? .clear).opacity(0.45), radius: selected ? 14 : 8, y: 4)
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.white, teal).padding(5)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(selected ? 1.04 : 1)
        }
        .buttonStyle(MolibooSpringPressStyle())
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
        .foregroundStyle(period.isDark ? .white : .primary)
    }

    // MARK: Navigation

    private func open(_ s: Section) {
        switch s {
        case .home: break
        case .studio: openStudio(.studio(characterID))
        case .wardrobe: openStudio(.wardrobe(characterID))
        case .stickers, .care: sheet = s
        }
    }

    private func openStudio(_ r: Route) {
        guard MolibooRegistry.descriptor(for: characterID) != nil else {
            flash("\(displayName)'s Studio is coming soon.")
            return
        }
        route = r
    }

    @ViewBuilder private func destination(_ r: Route) -> some View {
        switch r {
        case .studio(let id): MolibooLivingStudioView(characterID: id).navigationTransition(.zoom(sourceID: "world.hero", in: zoomNS))
        case .wardrobe(let id): MolibooLivingStudioView(characterID: id, initialPanel: .wardrobe).navigationTransition(.zoom(sourceID: "world.hero", in: zoomNS))
        case .photo(let id): MolibooLivingStudioView(characterID: id, startInPhoto: true).navigationTransition(.zoom(sourceID: "world.hero", in: zoomNS))
        case .collection: MolibooCollectionView()
        case .cards: MolibooCardBinderView()
        case .settings: MolibooSettingsView()
        }
    }

    @ViewBuilder private func sectionSheet(_ s: Section) -> some View {
        switch s {
        case .care: MolibooCareSheet(characterID: characterID, name: displayName, care: care) { a in doActivity(a) }
        case .stickers: MolibooStickerSheet(characterID: characterID, name: displayName) { flash($0) }
        default: EmptyView()
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
        return v > 0 ? v : 20
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
