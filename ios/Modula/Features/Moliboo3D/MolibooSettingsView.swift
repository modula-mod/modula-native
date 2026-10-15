import SwiftUI

/// Settings → Moliboo. Its own home for everything Moliboo: choose, wardrobe/Studio, 3D, motion, sounds/haptics,
/// Home companion, and a preview of the Originals collection. Storage keys are the existing mascot keys (unchanged),
/// so saved choices, outfits and entitlements carry over.
enum MolibooSettings {
    static let animationsKey = "moliboo.playfulAnimations"
    static let hapticsKey = "moliboo.haptics"
    static let onboardedKey = "moliboo.onboarded.v1"
}

struct MolibooSettingsView: View {
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    @AppStorage(MolibooFeatureFlags.native3DKey) private var native3D = MolibooFeatureFlags.native3DDefault
    @AppStorage(MolibooSettings.animationsKey) private var playful = true
    @AppStorage(MolibooSettings.hapticsKey) private var haptics = true
    @AppStorage(MolibooSettings.onboardedKey) private var onboarded = false
    @AppStorage(ModulaMascotSettings.nodusKey) private var nodus = true
    @AppStorage(ModulaMascotSettings.commentsKey) private var comments = false
    @AppStorage(ModulaMascotSettings.otherKey) private var other = false
    @AppStorage(ModulaMascotSettings.homeCompanionKey) private var homeCompanion = true
    @AppStorage(ModulaMascotSettings.soundsKey) private var sounds = true
    @AppStorage(ModulaMascotSettings.debugPremiumKey) private var debugPremium = false
    @AppStorage(MascotProfileSettings.showOnProfileKey) private var showOnProfile = true
    @AppStorage(MascotProfileSettings.useAsAvatarKey) private var asAvatar = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var hop = false
    @State private var cheer = 0
    @State private var showOnboarding = false
    @State private var premiumKind: ModulaMascotKind?
    @State private var route: Route?
    @State private var segment: MolibooHubSegment = .collection
    @State private var search = ""
    @State private var searching = false
    @State private var sort: Sort = .catalogue
    @State private var heart = false
    @State private var scrollY: CGFloat = 0
    @Namespace private var glassNS
    private var care = MolibooCareStore.shared

    enum Route: Hashable { case studio3D(String), studio(MascotStudioView.StudioTab), collection, cards }
    enum Sort: String, CaseIterable { case catalogue = "Catalogue", name = "Name", premium = "Premium first" }

    private var kind: ModulaMascotKind? { ModulaMascotKind(rawValue: kindRaw) }
    private var motionOn: Bool { playful && !reduceMotion }
    private var animating: Bool { motionOn && scenePhase == .active && route == nil }
    private let grid = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    private let cards = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    private var kinds: [ModulaMascotKind] {
        var ks = ModulaMascotKind.allCases.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.personality.localizedCaseInsensitiveContains(search) }
        switch sort {
        case .catalogue: break
        case .name: ks.sort { $0.name < $1.name }
        case .premium: ks.sort { ($0.isPremium ? 0 : 1, $0.name) < ($1.isPremium ? 0 : 1, $1.name) }
        }
        return ks
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    segmentBar(proxy).padding(.horizontal, 14).offset(y: -22).zIndex(1)
                    sheet.offset(y: -10)
                }
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                if route == nil, abs(y - scrollY) >= 2 { scrollY = y }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .top) {
            GeometryReader { g in
                Rectangle().fill(.bar).frame(height: g.safeAreaInsets.top).offset(y: -g.safeAreaInsets.top)
            }
            .frame(height: 0)
            .opacity(scrollY > 330 ? 1 : 0).animation(.easeOut(duration: 0.2), value: scrollY > 330)
            .allowsHitTesting(false).accessibilityHidden(true)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle("Moliboo")
        .accessibilityIdentifier("settings.moliboo")
        .navigationDestination(item: $route) { r in
            switch r {
            case .studio3D(let id): MolibooLivingStudioView(characterID: id)
            case .studio(let tab): MolibooStudioEntry(tab: tab)
            case .collection: MolibooCollectionView()
            case .cards: MolibooCardBinderView()
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: cheer) { _, _ in haptics }
        .sheet(isPresented: $showOnboarding) { MolibooWelcomeSheet { onboarded = true; showOnboarding = false } }
        .sheet(item: $premiumKind) { MascotPremiumSheet(kind: $0) }
        .onAppear {
            if !onboarded { showOnboarding = true }
            care.refresh(kindRaw)
            MascotProgressStore.shared.touchDay()
            _ = MascotWardrobeStore.shared.applyOutfitOfTheDayIfNeeded()
            _ = MascotWardrobeStore.shared.applyBirthdayOutfitIfNeeded(birthday: MascotAssistantStore.shared.context.birthday)
        }
        .task(id: animating) { await ambient() }
    }

    // MARK: Hero

    private var hero: some View {
        let state = care.state(for: kindRaw)
        return ZStack(alignment: .top) {
            MolibooGardenScene(animating: animating, parallax: min(0, scrollY) * -0.2 + max(0, scrollY) * 0.15)
            VStack(spacing: 0) {
                HStack {
                    MolibooHubBackButton()
                    Spacer()
                    Image("MoliboosLogo").resizable().scaledToFit().frame(height: 30)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .modulaGlass(in: Capsule(), interactive: false, specular: true)
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "sparkle").font(.system(size: 13, weight: .bold)).foregroundStyle(.yellow)
                                .scaleEffect(heart ? 1.2 : 0.8).opacity(heart ? 1 : 0.6).offset(x: 10, y: -8)
                        }
                        .accessibilityLabel("Moliboos").accessibilityIdentifier("moliboo.hub.logo")
                    Spacer()
                    Menu {
                        Button { showOnboarding = true } label: { Label("Replay the welcome", systemImage: "party.popper") }
                    } label: {
                        Image(systemName: "ellipsis").font(.headline).foregroundStyle(.primary).frame(width: 44, height: 44)
                    }
                    .modulaGlass(in: Circle(), specular: true)
                    .accessibilityLabel("More").accessibilityIdentifier("moliboo.hub.more")
                }
                .padding(.horizontal, 14).padding(.top, 58)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your\nMoliboos").font(.system(.largeTitle, design: .rounded).weight(.heavy))
                            .foregroundStyle(.white).shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                        Text("Small friends.\nBig moments.").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    }
                    .padding(.top, 18)
                    Spacer()
                    if kind != nil { statsCard(state) }
                }
                .padding(.horizontal, 16)
                Spacer(minLength: 0)
            }
            stage.padding(.top, 150)
        }
        .frame(height: 400)
        .clipped()
    }

    private var stage: some View {
        ZStack {
            MolibooMossRock(pulse: heart && motionOn).offset(y: 80)
            if let kind {
                MolibooHubArt(kind: kind, size: 170).offset(y: 14)
                    .offset(y: hop && motionOn ? -16 : 0)
                    .rotationEffect(.degrees(hop && motionOn ? -5 : 0))
                    .id(kind).transition(.scale.combined(with: .opacity))
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "heart.fill").font(.system(size: 14)).foregroundStyle(.pink)
                            .padding(8).modulaGlass(in: Circle(), interactive: false)
                            .scaleEffect(heart ? 1 : 0.6).opacity(heart ? 1 : 0)
                            .offset(x: 6, y: 10)
                    }
            } else {
                Image(systemName: "moon.zzz").font(.largeTitle).foregroundStyle(.white).padding(.top, 40)
            }
        }
        .frame(width: 240, height: 200)
        .contentShape(Rectangle())
        .onTapGesture { boop() }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("moliboo.hub.stage")
        .accessibilityLabel(kind.map { "\($0.name). Tap to say hi." } ?? "No Moliboo chosen")
        .animation(motionOn ? .spring(response: 0.32, dampingFraction: 0.5) : nil, value: hop)
        .animation(motionOn ? .easeInOut(duration: 1.2) : nil, value: heart)
        .animation(motionOn ? .snappy : nil, value: kindRaw)
        .onChange(of: kindRaw) { _, _ in boop(); care.refresh(kindRaw) }
    }

    private func statsCard(_ s: MolibooCareState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            stat("heart.fill", .pink, "\(Int(s.mood.rounded()))%", "Mood")
            stat("bolt.fill", .yellow, "\(Int(s.energy.rounded()))%", "Energy")
            stat("star.fill", .orange, "Lv. \(s.bondLevel)", "Bond")
        }
        .padding(12)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false, specular: true)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("moliboo.hub.stats")
    }

    private func stat(_ icon: String, _ c: Color, _ value: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(c).frame(width: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.subheadline.weight(.bold)).monospacedDigit()
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func boop() {
        cheer += 1
        guard motionOn else { return }
        hop = true
        Task { try? await Task.sleep(for: .milliseconds(260)); hop = false }
    }

    /// Occasional emotes: heart bubble, pedestal glow and sparkle. Stops when the scene or motion goes away.
    private func ambient() async {
        guard animating else { heart = false; return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 3.5...6)))
            if Task.isCancelled { return }
            heart = true
            if Bool.random() { hop = true; try? await Task.sleep(for: .milliseconds(260)); hop = false }
            try? await Task.sleep(for: .seconds(1.6))
            heart = false
        }
    }

    // MARK: Segments

    private func segmentBar(_ proxy: ScrollViewProxy) -> some View {
        ModulaGlassGroup(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(MolibooHubSegment.allCases) { s in
                    Button { pick(s, proxy) } label: {
                        Label(s.title, systemImage: s.icon).labelStyle(.titleAndIcon)
                            .font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.6)
                            .foregroundStyle(segment == s ? Color.white : Color.primary)
                            .padding(.horizontal, 4).frame(maxWidth: .infinity, minHeight: 40)
                            .background {
                                if segment == s {
                                    Capsule().fill(Color.clear)
                                        .modulaGlass(in: Capsule(), tint: Color(red: 0.16, green: 0.62, blue: 0.85), prominent: true)
                                        .modulaGlassID("hub.segment", in: glassNS)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("moliboo.hub.segment.\(s.rawValue)")
                    .accessibilityAddTraits(segment == s ? .isSelected : [])
                }
            }
            .padding(4)
            .modulaGlass(in: Capsule(), interactive: false, specular: true)
        }
    }

    private func pick(_ s: MolibooHubSegment, _ proxy: ScrollViewProxy) {
        withAnimation(motionOn ? .spring(response: 0.38, dampingFraction: 0.78) : nil) { segment = s }
        HapticEngine.shared.play(.selection)
        switch s {
        case .collection: withAnimation { proxy.scrollTo("hub.grid", anchor: .top) }
        case .settings: withAnimation { proxy.scrollTo("hub.show", anchor: .top) }
        case .originals: withAnimation { proxy.scrollTo("hub.originals", anchor: .top) }
        case .studio:
            if native3D, let d = MolibooRegistry.descriptor(for: kindRaw) { route = .studio3D(d.id) } else { route = .studio(.wardrobe) }
            segment = .collection
        }
    }

    // MARK: Sheet

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            collectionHeader.id("hub.grid")
            if searching {
                ModulaGlassSearchField(prompt: "Search Moliboos", text: $search).transition(.move(edge: .top).combined(with: .opacity))
            }
            LazyVGrid(columns: grid, spacing: 8) {
                ForEach(kinds) { k in characterCard(k) }
            }
            HStack(spacing: 8) {
                offCard.frame(maxWidth: .infinity)
                createCard.frame(maxWidth: .infinity)
                unlockBanner.frame(maxWidth: .infinity).layoutPriority(1)
            }
            .frame(height: 104)

            if kind != nil {
                sectionTitle("Show Moliboo on").id("hub.show")
                ModulaGlassGroup {
                    LazyVGrid(columns: cards, spacing: 8) {
                        toggleCard("bubble.left.and.text.bubble.right.fill", .purple, "Nodus", "Your AI companion", $nodus, "moliboo.hub.show.nodus")
                        toggleCard("text.bubble.fill", .blue, "Comment inputs", "Chats & comments", $comments, "moliboo.hub.show.comments")
                        toggleCard("pencil.line", .teal, "Other composers", "Posts, notes, etc.", $other, "moliboo.hub.show.other")
                        toggleCard("house.fill", .orange, "Home companion", "Walks along Home", $homeCompanion, "moliboo.hub.show.home")
                            .accessibilityHint("Your Moliboo walks along the bottom of Home, peeks over posts and naps when idle.")
                    }
                }
            } else {
                Color.clear.frame(height: 0).id("hub.show")
            }

            HStack(spacing: 8) {
                wideCard("tshirt.fill", .blue, "Moliboo Studio", "Dress up, create custom Moliboos and unlock new items.", art: kind, id: "moliboo.hub.studio") { route = .studio(.wardrobe) }
                wideCard("bubble.left.and.text.bubble.right.fill", .teal, "Assistant & keywords", "Keyword draft-replies for comments on your posts.", art: nil, id: "moliboo.hub.assistant") { route = .studio(.assistant) }
            }

            if MolibooCardFlags.enabled {
                wideCard("rectangle.portrait.on.rectangle.portrait.angled.fill", .orange, "Trading Cards", "Collect the Founding Collection. Open a free pack.", art: .pebble, id: "moliboo.hub.cards") { route = .cards }
            }

            sectionTitle("Profile Moliboo")
            ModulaGlassGroup {
                LazyVGrid(columns: cards, spacing: 8) {
                    toggleCard("person.crop.circle.fill", .indigo, "Show on Profile", "With its scene", $showOnProfile, "moliboo.hub.profile.show")
                    toggleCard("person.crop.square.fill", .pink, "Use as avatar", "Long-press for wardrobe", $asAvatar, "moliboo.hub.profile.avatar")
                }
            }

            sectionTitle("Motion & feel")
            ModulaGlassGroup {
                LazyVGrid(columns: cards, spacing: 8) {
                    toggleCard("figure.dance", .orange, "Playful animations", reduceMotion ? "Calm: Reduce Motion is on" : "Hops & celebrations", $playful, "moliboo.hub.playful")
                    toggleCard("hand.tap.fill", .purple, "Haptics", "Little taps", $haptics, "moliboo.hub.haptics")
                    toggleCard("speaker.wave.2.fill", .green, "Moliboo sounds", "Follow silent switch", $sounds, "moliboo.hub.sounds")
                    #if DEBUG
                    toggleCard("crown.fill", .yellow, "Unlock Premium", "Debug builds only", $debugPremium, "moliboo.hub.debugPremium")
                    #endif
                }
            }

            sectionTitle("3D & Advanced")
            ModulaGlassGroup {
                LazyVGrid(columns: cards, spacing: 8) {
                    toggleCard("cube.transparent.fill", .blue, "3D Moliboos", native3D ? "Enable 3D characters" : "Classic 2D look", $native3D, "moliboo.settings.3d")
                }
            }
            if native3D {
                Text("3D is ready for \(MolibooRegistry.available3D.map(\.displayName).formatted(.list(type: .and))).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            sectionTitle("The Originals").id("hub.originals")
            originals
            Text("25 founding Moliboos. Collect them as they arrive.").font(.caption).foregroundStyle(.secondary)

            Button { showOnboarding = true } label: {
                Label("Replay the welcome", systemImage: "party.popper.fill").font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(MolibooSpringPress(enabled: motionOn))
            .modulaGlass(in: Capsule(), specular: true)
            .accessibilityIdentifier("moliboo.hub.replay")
        }
        .padding(16).padding(.bottom, 30)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
                .fill(Color(uiColor: .systemGroupedBackground))
                .shadow(color: .black.opacity(0.08), radius: 10, y: -4)
        )
        .animation(motionOn ? .spring(response: 0.4, dampingFraction: 0.8) : nil, value: searching)
        .animation(motionOn ? .spring(response: 0.4, dampingFraction: 0.8) : nil, value: sort)
    }

    private var collectionHeader: some View {
        HStack(spacing: 8) {
            Text("Your Moliboos").font(.title3.weight(.bold))
            Spacer()
            ModulaGlassIconButton(title: "Search", systemImage: "magnifyingglass", size: 36) { searching.toggle(); if !searching { search = "" } }
                .accessibilityIdentifier("moliboo.hub.search")
            Menu {
                Picker("Sort", selection: $sort) { ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down").font(.footnote.weight(.semibold)).foregroundStyle(.primary)
                    .padding(.horizontal, 12).frame(height: 36)
            }
            .modulaGlass(in: Capsule(), specular: true)
            .accessibilityIdentifier("moliboo.hub.sort")
            ModulaGlassIconButton(title: "Create custom Moliboo", systemImage: "plus", size: 36, tint: .blue, foreground: .white) { route = .studio(.custom) }
                .accessibilityIdentifier("moliboo.hub.add")
        }
    }

    private func characterCard(_ k: ModulaMascotKind) -> some View {
        let selected = kindRaw == k.rawValue
        let locked = !MascotEntitlements.canUse(k)
        return Button {
            if locked { premiumKind = k; HapticEngine.shared.play(.warning); return }
            withAnimation(motionOn ? .spring(response: 0.4, dampingFraction: 0.72) : nil) { kindRaw = k.rawValue }
            MascotSound.shared.play(.pick)
            HapticEngine.shared.play(.selection)
        } label: {
            VStack(spacing: 3) {
                MolibooHubArt(kind: k, size: 58)
                Text(k.name).font(.footnote.weight(.bold)).lineLimit(1)
                Text(k.personality).font(.system(size: 9)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(2)
                    .frame(minHeight: 22, alignment: .top)
                if k.isPremium {
                    Label(locked ? "Premium" : "Premium", systemImage: locked ? "lock.fill" : "crown.fill")
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(.orange)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange.opacity(0.14)))
                }
            }
            .padding(.vertical, 8).padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [k.palette.light.opacity(0.95), k.palette.mid.opacity(0.35)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? Color.accentColor : Color.white.opacity(0.6), lineWidth: selected ? 2.5 : 1))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                        .frame(width: 20, height: 20).background(Circle().fill(Color.accentColor)).padding(5)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .scaleEffect(selected ? 1.0 : 0.97)
        }
        .buttonStyle(MolibooSpringPress(enabled: motionOn))
        .accessibilityIdentifier("moliboo.hub.char.\(k.rawValue)")
        .accessibilityLabel("\(k.name)\(k.isPremium ? ", Premium" : ""). \(k.personality)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var offCard: some View {
        let selected = kind == nil
        return Button {
            withAnimation(.snappy) { kindRaw = ModulaMascotSettings.off }
            HapticEngine.shared.play(.selection)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "eye.slash").font(.title2).foregroundStyle(.secondary)
                Text("Off").font(.footnote.weight(.bold))
                Text("No Moliboo").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2.5))
        }
        .buttonStyle(MolibooSpringPress(enabled: motionOn))
        .accessibilityIdentifier("moliboo.hub.off")
        .accessibilityLabel("Moliboo off")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var createCard: some View {
        Button { route = .studio(.custom) } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus").font(.headline).foregroundStyle(.white).frame(width: 30, height: 30).background(Circle().fill(Color.blue.opacity(0.75)))
                Text("Create\nCustom Moliboo").font(.system(size: 10, weight: .semibold)).multilineTextAlignment(.center).foregroundStyle(.blue)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.blue.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
        .buttonStyle(MolibooSpringPress(enabled: motionOn))
        .accessibilityIdentifier("moliboo.hub.create")
    }

    private var unlockBanner: some View {
        let lockedKind = ModulaMascotKind.allCases.first { !MascotEntitlements.canUse($0) }
        return Button { if let lockedKind { premiumKind = lockedKind } } label: {
            ZStack(alignment: .leading) {
                LinearGradient(colors: [Color(red: 0.55, green: 0.45, blue: 0.95), Color(red: 0.95, green: 0.6, blue: 0.85)], startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(spacing: -14) {
                    Spacer()
                    ForEach([ModulaMascotKind.nimbus, .pip], id: \.self) { MolibooHubArt(kind: $0, size: 52) }
                }
                .padding(.trailing, 2)
                Text(lockedKind == nil ? "All Moliboos\nunlocked" : "Unlock more\nMoliboos").font(.footnote.weight(.heavy)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 2).padding(.leading, 10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(MolibooSpringPress(enabled: motionOn))
        .disabled(lockedKind == nil)
        .accessibilityIdentifier("moliboo.hub.unlock")
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s).font(.headline).padding(.top, 4)
    }

    private func toggleCard(_ icon: String, _ c: Color, _ title: String, _ sub: String, _ on: Binding<Bool>, _ id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(c)
                    .frame(width: 30, height: 30).background(Circle().fill(c.opacity(0.15)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.footnote.weight(.semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack { Spacer(); Toggle(title, isOn: on).labelsHidden().accessibilityIdentifier(id) }
        }
        .padding(10).frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: false)
    }

    private func linkCard(_ icon: String, _ c: Color, _ title: String, _ sub: String, _ id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(c)
                    .frame(width: 32, height: 32).background(Circle().fill(c.opacity(0.15)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.footnote.weight(.semibold)).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 96).contentShape(Rectangle())
        }
        .buttonStyle(MolibooSpringPress(enabled: motionOn))
        .foregroundStyle(.primary)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier(id)
    }

    private func wideCard(_ icon: String, _ c: Color, _ title: String, _ sub: String, art: ModulaMascotKind?, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30).background(Circle().fill(c.gradient))
                    Spacer()
                    if let art { MolibooHubArt(kind: art, size: 44) }
                    else { Image(systemName: "ellipsis.bubble.fill").font(.system(size: 26)).foregroundStyle(c.gradient) }
                }
                Text(title).font(.footnote.weight(.bold)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.8)
                Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
            }
            .padding(10).frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(LinearGradient(colors: [c.opacity(0.18), c.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(MolibooSpringPress(enabled: motionOn))
        .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityIdentifier(id)
    }

    private var originals: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(MolibooCosmetics.originals.enumerated()), id: \.offset) { i, id in
                    let k = ModulaMascotKind(rawValue: id)
                    Button { if k != nil { kindRaw = id } } label: {
                        VStack(spacing: 3) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous).fill((k?.palette.light ?? .gray).opacity(0.5))
                                if native3D, let img = MolibooPortrait.image(for: id) { Image(uiImage: img).resizable().scaledToFit().padding(4) }
                                else if let k { ModulaMascotFigure(kind: k, pose: .still(), size: 22) }
                                else { Image(systemName: "questionmark").font(.title3.weight(.bold)).foregroundStyle(.tertiary) }
                            }
                            .frame(width: 64, height: 64)
                            Text(String(format: "%03d", i + 1)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            Text(k != nil ? id.prefix(1).uppercased() + id.dropFirst() : "Soon").font(.caption2.weight(.semibold)).foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(MolibooSpringPress(enabled: motionOn))
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// Reads `dismiss` in its own view (a parent that reads it while pushing destinations loops; see MOL-03 World).
private struct MolibooHubBackButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left").font(.headline).foregroundStyle(.primary).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .modulaGlass(in: Circle(), specular: true)
        .accessibilityIdentifier("moliboo.hub.back").accessibilityLabel("Back")
    }
}

/// One-time welcome moment (also replayable from Settings → Moliboo): a magical, animated intro over the dreamy /
/// night ambient sky. Three swipe pages (meet, dress up, care), characters float in with a bob and tilt parallax,
/// text reveals in a stagger, and on "Let's go" the chosen Moliboo grows into the hero spot before the sheet closes.
/// Reduce Motion: no float, bob, parallax or morph; content simply appears.
struct MolibooWelcomeSheet: View {
    var done: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(MolibooSettings.animationsKey) private var playful = true
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    @State private var appear = false
    @State private var page = 0
    @State private var launching = false
    @State private var bob = false
    @Namespace private var morph
    private var motionOn: Bool { playful && !reduceMotion }
    /// Registered characters only (portraits when 3D assets exist, 2D otherwise).
    private var trio: [String] {
        let ids = MolibooRegistry.available3D.map(\.id)
        let pick = ["pip", "pebble", "moss"].filter { ids.isEmpty || ids.contains($0) }
        return pick.isEmpty ? Array(ids.prefix(3)) : pick
    }
    private let pages: [(String, String, String)] = [
        ("Little friends, big feelings.", "Meet your Moliboo. It notices what you do and keeps you company across Modula.", "heart.fill"),
        ("Dress them up.", "Hats, outfits and backgrounds in the Studio, in real 3D. Save looks and share photos.", "tshirt.fill"),
        ("Care for them.", "Play, feed and tuck them in. Their mood and your bond grow day by day.", "leaf.fill")
    ]

    var body: some View {
        ZStack {
            MolibooAmbientBackground(ambience: .night, animated: motionOn, fps: 20, density: 0.9)
                .overlay(MolibooAmbientBackground(ambience: .dreamy, animated: motionOn, fps: 12, showsSky: false, density: 0.5).opacity(0.7))
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Image("MoliboosLogo").resizable().scaledToFit().frame(height: 52)
                    .shadow(color: .white.opacity(0.7), radius: 8).shadow(color: Color(red: 0.6, green: 0.5, blue: 1).opacity(0.8), radius: 22)
                    .scaleEffect(appear ? 1 : 0.8).opacity(appear ? 1 : 0)
                    .accessibilityLabel("Moliboos")
                    .padding(.top, 36)
                stage.frame(height: 220)
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { i in pageText(i).tag(i) }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .frame(height: 190)
                .opacity(launching ? 0 : 1)
                Spacer(minLength: 0)
                Button(action: go) {
                    Text(page < pages.count - 1 ? "Next" : "Let’s go").font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 54).contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .modulaGlass(in: Capsule(), interactive: true, tint: Color(red: 0.45, green: 0.35, blue: 0.95), prominent: true, specular: true)
                .shadow(color: Color(red: 0.5, green: 0.4, blue: 1).opacity(0.6), radius: 18, y: 6)
                .padding(.horizontal, 28)
                .accessibilityIdentifier("moliboo.welcome.go")
                if page < pages.count - 1 {
                    Button("Skip") { finish() }.font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.75))
                        .accessibilityIdentifier("moliboo.welcome.skip")
                }
            }
            .padding(.bottom, 24)
        }
        .environment(\.colorScheme, .dark)
        .presentationDetents([.large])
        .presentationBackground(.clear)
        .onAppear {
            withAnimation(motionOn ? .spring(response: 0.7, dampingFraction: 0.75) : nil) { appear = true }
            if motionOn { bob = true }
        }
        .sensoryFeedback(.success, trigger: appear)
        .sensoryFeedback(.selection, trigger: page)
    }

    /// The floating trio; with "Let's go" the selected one grows into the hero spot (matched geometry morph).
    private var stage: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                Ellipse().fill(RadialGradient(colors: [Color(red: 0.6, green: 0.9, blue: 1).opacity(0.45), .clear], center: .center, startRadius: 4, endRadius: 140))
                    .frame(width: 280, height: 80).offset(y: 86)
                if launching {
                    art(hero).matchedGeometryEffect(id: hero, in: morph).frame(width: 190, height: 190)
                } else {
                    ForEach(Array(trio.enumerated()), id: \.element) { i, id in
                        let center = i == 1
                        art(id)
                            .matchedGeometryEffect(id: id, in: morph)
                            .frame(width: center ? 150 : 104, height: center ? 150 : 104)
                            .offset(x: CGFloat(i - 1) * w * 0.3 + CGFloat(page - 1) * -10 * CGFloat(i - 1),
                                    y: (center ? -6 : 22) + (bob ? -6 : 4) * (i == 1 ? 1 : 0.7))
                            .offset(y: appear ? 0 : 160)
                            .opacity(appear ? 1 : 0)
                            .animation(motionOn ? .spring(response: 0.8, dampingFraction: 0.62).delay(0.15 + Double(i) * 0.12) : nil, value: appear)
                            .animation(motionOn ? .easeInOut(duration: 1.6 + Double(i) * 0.3).repeatForever(autoreverses: true) : nil, value: bob)
                            .animation(motionOn ? .spring(response: 0.5, dampingFraction: 0.8) : nil, value: page)
                            .onTapGesture { kindRaw = id }
                            .overlay(alignment: .bottom) {
                                if id == hero { Circle().fill(.white).frame(width: 6, height: 6).offset(y: 10) }
                            }
                    }
                }
            }
            .frame(width: w, height: geo.size.height)
        }
        .accessibilityHidden(true)
    }

    private var hero: String { trio.contains(kindRaw) ? kindRaw : (trio.dropFirst().first ?? trio.first ?? "pip") }

    @ViewBuilder private func art(_ id: String) -> some View {
        if let img = MolibooPortrait.image(for: id) {
            Image(uiImage: img).resizable().interpolation(.high).scaledToFit()
                .shadow(color: .black.opacity(0.35), radius: 10, y: 8)
                .shadow(color: (ModulaMascotKind(rawValue: id)?.palette.light ?? .white).opacity(0.5), radius: 16)
        } else if let k = ModulaMascotKind(rawValue: id) {
            ModulaMascotFigure(kind: k, pose: .still(), size: 60)
        }
    }

    private func pageText(_ i: Int) -> some View {
        let p = pages[i]
        let shown = appear && page == i
        return VStack(spacing: 10) {
            Image(systemName: p.2).font(.title3).foregroundStyle(.pink)
                .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 10)
                .animation(motionOn ? .easeOut(duration: 0.4).delay(0.05) : nil, value: shown)
            Text(p.0).font(.system(.title2, design: .rounded).weight(.heavy)).foregroundStyle(.white).multilineTextAlignment(.center)
                .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 14)
                .animation(motionOn ? .easeOut(duration: 0.45).delay(0.15) : nil, value: shown)
            Text(p.1).font(.body).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center).padding(.horizontal, 28)
                .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 14)
                .animation(motionOn ? .easeOut(duration: 0.45).delay(0.3) : nil, value: shown)
        }
        .accessibilityElement(children: .combine)
    }

    private func go() {
        if page < pages.count - 1 { withAnimation(motionOn ? .spring : nil) { page += 1 } } else { finish() }
    }

    private func finish() {
        guard motionOn else { done(); return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { launching = true }
        Task { try? await Task.sleep(for: .milliseconds(650)); done() }
    }
}
