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
    enum Route: Hashable { case studio(String), wardrobe(String), photo(String), settings }

    @Environment(AppEnvironment.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    @AppStorage("moliboo.world.navCollapsed") private var navCollapsed = false
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
    #if DEBUG
    @AppStorage("moliboo.world.debugHour") private var debugHour = -1
    #endif

    private var characterID: String { kindRaw }
    private var kind: ModulaMascotKind? { ModulaMascotKind(rawValue: kindRaw) }
    private var displayName: String { MolibooRegistry.descriptor(for: characterID)?.displayName ?? kind?.name ?? "Moliboo" }
    private var careState: MolibooCareState { care.state(for: characterID) }
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
            MolibooWorldBackdrop(period: period, scrollY: scrollY, animating: motionAllowed && stage.awake)
            ScrollView {
                VStack(spacing: 16) {
                    header
                    stageArea
                    identityCard
                    composer
                    quickActions
                    activities
                    collection
                }
                .padding(.horizontal, 16).padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in scrollY = y }
            if let toast { toastView(toast) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $route) { r in destination(r) }
        .sheet(isPresented: $showSwitcher) { switcher.presentationDetents([.medium]) }
        .sheet(item: $sheet) { s in sectionSheet(s).presentationDetents([.medium, .large]) }
        .task {
            if chat == nil { chat = MolibooChatModel(backend: MolibooIntelligenceChatBackend(service: app.intelligence)) }
            care.refresh(characterID)
            stage.wake(allowed: motionAllowed)
        }
        .onChange(of: scenePhase) { _, p in
            if p == .active { care.refresh(characterID); stage.wake(allowed: motionAllowed) } else { stage.sleepNow() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .onChange(of: kindRaw) { _, _ in care.refresh(characterID); stage.react(.happy, allowed: motionAllowed) }
        .onChange(of: chat?.draft ?? "") { _, _ in stage.poke(allowed: motionAllowed) }
        .onDisappear { stage.sleepNow(); chat?.cancel() }
        #if DEBUG
        .overlay(alignment: .bottomTrailing) { probe }
        #endif
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Image("MoliboosLogo").resizable().scaledToFit().frame(height: 40)
                .accessibilityLabel("Moliboos").accessibilityIdentifier("world.logo")
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.headline).frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityIdentifier("world.back").accessibilityLabel("Back")
                Spacer()
                Menu {
                    Button { route = .settings } label: { Label("Moliboo settings", systemImage: "gearshape") }
                    Button { showSwitcher = true } label: { Label("Switch Moliboo", systemImage: "arrow.left.arrow.right") }
                } label: {
                    Image(systemName: "ellipsis").font(.headline).frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityIdentifier("world.more").accessibilityLabel("More")
            }
        }
        .foregroundStyle(period.isDark ? .white : .primary)
        .padding(.top, 6)
    }

    // MARK: Stage

    private var stageArea: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top, spacing: 8) {
                Color.clear.frame(width: navCollapsed ? 44 : 104)
                MolibooStageCharacter(characterID: characterID, emotion: emotion, stage: stage, animating: motionAllowed,
                                      gaze: chat?.isTyping == true ? 1 : 0)
                    .frame(maxWidth: .infinity).frame(height: 230)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { composerFocused = true; stage.react(.curious, allowed: motionAllowed) }
                    .onTapGesture { stage.bounce(allowed: motionAllowed); care.interact(characterID, mood: 1, bond: 1) }
                    .onLongPressGesture(minimumDuration: 0.5) { showSwitcher = true }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(displayName), \(emotion.label)")
                    .accessibilityHint("Tap to bounce, double-tap to chat, hold to switch Moliboo")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("world.stage")
                statusPanel
            }
            floatingNav
        }
    }

    private var floatingNav: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Section.allCases) { s in
                Button { open(s) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: s.symbol).frame(width: 20)
                        if !navCollapsed { Text(s.title).font(.footnote.weight(.semibold)).lineLimit(1) }
                    }
                    .padding(.horizontal, 10).frame(height: 36)
                    .frame(maxWidth: navCollapsed ? 44 : 104, alignment: .leading)
                    .background(s == .home ? AnyShapeStyle(.white.opacity(0.35)) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("world.nav.\(s.rawValue)").accessibilityLabel(s.title)
            }
            Button { withAnimation(reduceMotion ? nil : .snappy) { navCollapsed.toggle() } } label: {
                Image(systemName: navCollapsed ? "chevron.right" : "chevron.left").font(.caption.weight(.bold))
                    .frame(width: navCollapsed ? 44 : 104, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("world.nav.toggle").accessibilityLabel(navCollapsed ? "Expand menu" : "Collapse menu")
        }
        .padding(4)
        .foregroundStyle(period.isDark ? .white : .primary)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.35), lineWidth: 0.5))
    }

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            stat("heart.fill", .pink, "\(Int(careState.mood))%", "Mood", id: "mood")
            stat("bolt.fill", .yellow, "\(Int(careState.energy))%", "Energy", id: "energy")
            stat("star.fill", .orange, "Lv. \(careState.bondLevel)", "Bond", id: "bond")
        }
        .padding(10)
        .frame(width: 92)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.35), lineWidth: 0.5))
        .padding(.top, 30)
    }

    private func stat(_ symbol: String, _ tint: Color, _ value: String, _ label: String, id: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(tint).font(.footnote)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.caption.weight(.bold)).monospacedDigit()
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("world.stat.\(id)")
    }

    // MARK: Identity

    private var traits: [(String, String)] {
        let mood = MolibooRegistry.descriptor(for: characterID).map { MolibooIdlePersonality.for($0).mood.capitalized } ?? "Gentle"
        return [("leaf.fill", mood), (emotion.symbol, emotion.label), ("star.fill", "Always with you")]
    }

    private var identityCard: some View {
        VStack(spacing: 6) {
            (Text("Hi, I'm ") + Text(displayName).foregroundStyle(Color(red: 0.25, green: 0.80, blue: 0.85)) + Text("!"))
                .font(.title2.weight(.bold))
                .accessibilityIdentifier("world.identity.name")
            Text(kind?.personality ?? "A brand new Moliboo friend.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 6) {
                ForEach(traits, id: \.1) { t in
                    Label(t.1, systemImage: t.0).font(.caption2.weight(.semibold)).lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.white.opacity(0.18), in: Capsule())
                }
            }
            .accessibilityIdentifier("world.identity.traits")
        }
        .padding(14).frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.35), lineWidth: 0.5))
    }

    // MARK: Composer

    @ViewBuilder private var composer: some View {
        if let chat {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").foregroundStyle(.cyan).frame(width: 34, height: 34)
                        .background(.white.opacity(0.18), in: Circle())
                    TextField("Type to see it watch…", text: Binding(get: { chat.draft }, set: { chat.draft = $0; if chat.phase != .composing && !$0.isEmpty { chat.reset() } }))
                        .focused($composerFocused)
                        .submitLabel(.send)
                        .onSubmit { send() }
                        .accessibilityIdentifier("world.composer.field")
                    Button { send() } label: {
                        Group {
                            if chat.phase == .submitting || chat.phase == .awaiting { ProgressView().tint(.white) }
                            else { Image(systemName: "arrow.up").font(.headline.weight(.bold)) }
                        }
                        .frame(width: 40, height: 40)
                        .background(chat.canSend ? Color.cyan : Color.gray.opacity(0.4), in: Circle())
                        .foregroundStyle(.white)
                    }
                    .disabled(!chat.canSend)
                    .accessibilityIdentifier("world.composer.send").accessibilityLabel("Send")
                }
                .padding(8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 0.5))
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
        .background(chat.phase == .composing ? AnyShapeStyle(.clear) : AnyShapeStyle(.ultraThinMaterial), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("world.chat.status")
    }

    private func send() {
        chat?.send(as: displayName) { stage.react(.excited, allowed: motionAllowed) }
        composerFocused = false
    }

    // MARK: Quick actions

    private var quickActions: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                quick("Say hi", "bubble.left.fill", id: "sayhi") {
                    care.interact(characterID, mood: 3, bond: 3); stage.react(.happy, allowed: motionAllowed); flash("\(displayName) waves back!")
                }
                quick("Play", "gamecontroller.fill", id: "play") { doActivity(.play) }
                quick("Give treat", "carrot.fill", id: "treat") { doActivity(.feed) }
                quick("Take photo", "camera.fill", id: "photo") { openStudio(.photo(characterID)) }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func quick(_ title: String, _ symbol: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.footnote.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("world.quick.\(id)")
    }

    // MARK: Activities (Care)

    private var activities: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Activities") { sheet = .care }
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(MolibooActivity.allCases) { a in activityCard(a) }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func activityCard(_ a: MolibooActivity) -> some View {
        Button { doActivity(a) } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(a.tint.gradient.opacity(0.55))
                    if let img = MolibooPortrait.image(for: characterID) {
                        Image(uiImage: img).resizable().scaledToFit().padding(10)
                    }
                    Image(systemName: a.symbol).font(.title3).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(8)
                }
                .frame(height: 86)
                Text(a == .sleep && careState.asleep ? "Wake up" : a.title).font(.subheadline.weight(.bold))
                Text(a.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(8).frame(width: 128)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("world.activity.\(a.rawValue)")
    }

    private func doActivity(_ a: MolibooActivity) {
        let ok = care.perform(a, for: characterID)
        if ok {
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
        }
    }

    private func collectionTile(_ id: String) -> some View {
        let selected = id == characterID
        return Button { kindRaw = id } label: {
            VStack(spacing: 4) {
                if let img = MolibooPortrait.image(for: id) { Image(uiImage: img).resizable().scaledToFit().frame(height: 62) }
                Text(MolibooRegistry.descriptor(for: id)?.displayName ?? id.capitalized).font(.caption.weight(.semibold))
                if ModulaMascotKind(rawValue: id)?.isPremium == true {
                    Label("Premium", systemImage: "crown.fill").font(.caption2).foregroundStyle(.orange)
                }
            }
            .padding(8).frame(width: 86)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Color.cyan : .white.opacity(0.3), lineWidth: selected ? 2 : 0.5))
            .overlay(alignment: .topTrailing) { if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.cyan).padding(4) } }
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
        guard MolibooRegistry.descriptor(for: characterID) != nil, MolibooFeatureFlags.native3DEnabled else {
            flash("\(displayName)'s Studio needs 3D Moliboos (Settings → Moliboo → 3D).")
            return
        }
        route = r
    }

    @ViewBuilder private func destination(_ r: Route) -> some View {
        switch r {
        case .studio(let id): MolibooLivingStudioView(characterID: id)
        case .wardrobe(let id): MolibooLivingStudioView(characterID: id, initialPanel: .wardrobe)
        case .photo(let id): MolibooLivingStudioView(characterID: id, startInPhoto: true)
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
        toast = s
        UIAccessibility.post(notification: .announcement, argument: s)
        Task { try? await Task.sleep(for: .seconds(2.2)); if toast == s { toast = nil } }
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

    func wake(allowed: Bool) {
        guard allowed else { sleepNow(); return }
        awake = true
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.awakeSeconds))
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
