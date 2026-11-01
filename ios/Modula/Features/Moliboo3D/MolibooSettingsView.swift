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
    private let native3D = MolibooFeatureFlags.native3DEnabled   // 2D-only: always false, no toggle
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
    @Environment(\.colorScheme) private var scheme
    @State private var hop = false
    @State private var cheer = 0
    @State private var showOnboarding = false
    @State private var premiumKind: ModulaMascotKind?
    @State private var route: Route?
    @State private var segment: MolibooHubSegment = .collection
    @State private var search = ""
    @State private var searching = false
    @State private var sort: Sort = .catalogue
    @Namespace private var glassNS
    private var care = MolibooCareStore.shared

    enum Route: Hashable { case studio3D(String), studio(MascotStudioView.StudioTab), collection, cards }
    enum Sort: String, CaseIterable { case catalogue = "Catalogue", name = "Name", premium = "Premium first" }

    private var kind: ModulaMascotKind? { ModulaMascotKind(rawValue: kindRaw) }
    private var motionOn: Bool { playful && !reduceMotion }
    private var animating: Bool { motionOn && scenePhase == .active && route == nil }
    private let grid = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var kinds: [ModulaMascotKind] {
        var ks = ModulaMascotKind.roster.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.personality.localizedCaseInsensitiveContains(search) || $0.title.localizedCaseInsensitiveContains(search) }
        switch sort {
        case .catalogue: ks.sort { $0.number < $1.number }
        case .name: ks.sort { $0.name < $1.name }
        case .premium: ks.sort { ($0.isPremium ? 0 : 1, $0.name) < ($1.isPremium ? 0 : 1, $1.name) }
        }
        return ks
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 28) {
                    selectedRow
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    segmentBar(proxy)
                        .padding(.horizontal, 20)

                    Group {
                        switch segment {
                        case .collection, .originals:
                            collectionSection.id("hub.grid")
                        case .settings:
                            settingsSection.id("hub.show")
                        case .studio:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .scrollIndicators(.hidden)
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            hubTopBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(uiColor: .systemGroupedBackground).opacity(0.94).ignoresSafeArea(edges: .top))
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
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
    }

    private var hubTopBar: some View {
        ZStack {
            MoliboosWordmark(height: 24)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("moliboo.hub.logo")
            HStack {
                MolibooHubBackButton()
                Spacer()
            }
        }
    }

    /// Hero: the chosen Moliboo on a soft card tinted from its own palette (adapts to light / dark).
    /// Labels sit below the art on the system surface — never on top of the colourful art — so they
    /// always read. Actions are a separate grouped glass capsule row, clearly apart from the art.
    private var selectedRow: some View {
        let state = care.state(for: kindRaw)
        let light = kind?.palette.light ?? Color(uiColor: .systemGray4)
        let mid = kind?.palette.mid ?? Color(uiColor: .systemGray3)
        return VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(LinearGradient(colors: [light.opacity(scheme == .dark ? 0.30 : 0.55), mid.opacity(scheme == .dark ? 0.16 : 0.28)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Ellipse()
                    .fill(Color.black.opacity(scheme == .dark ? 0.28 : 0.10))
                    .frame(width: 120, height: 16)
                    .blur(radius: 6)
                    .offset(y: 78)
                if let kind {
                    MolibooHubArt(kind: kind, size: 160)
                        .offset(y: hop && motionOn ? -14 : 0)
                        .rotationEffect(.degrees(hop && motionOn ? -4 : 0))
                        .id(kind)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                } else {
                    Image(systemName: "moon.zzz").font(.system(size: 44)).foregroundStyle(.secondary)
                }
            }
            .frame(height: 216)
            .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .onTapGesture { boop() }
            .animation(motionOn ? .spring(response: 0.32, dampingFraction: 0.55) : nil, value: hop)
            .animation(motionOn ? .snappy : nil, value: kindRaw)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("moliboo.hub.stage")
            .accessibilityLabel(kind.map { "\($0.name). Tap to say hi." } ?? "No Moliboo chosen")

            VStack(spacing: 4) {
                Text(kind?.name ?? "No Moliboo")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Text(kind.map { "\($0.family.name) · \($0.title)" } ?? "Choose one from the collection")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if kind != nil {
                    Text("Mood \(Int(state.mood.rounded()))%  ·  Energy \(Int(state.energy.rounded()))%  ·  Bond Lv \(state.bondLevel)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                        .accessibilityIdentifier("moliboo.hub.stats")
                }
            }
            .frame(maxWidth: .infinity)

            if kind != nil {
                ModulaGlassGroup(spacing: 10) {
                    HStack(spacing: 10) {
                        heroAction("tshirt.fill", "Studio", id: "moliboo.hub.studio") { route = .studio(.wardrobe) }
                        heroAction("bubble.left.and.text.bubble.right.fill", "Assistant", id: "moliboo.hub.assistant") { route = .studio(.assistant) }
                        if MolibooCardFlags.enabled {
                            heroAction("rectangle.portrait.on.rectangle.portrait.angled.fill", "Cards", id: "moliboo.hub.cards") { route = .cards }
                        }
                    }
                }
            }
        }
        .onChange(of: kindRaw) { _, _ in boop(); care.refresh(kindRaw) }
    }

    private func heroAction(_ icon: String, _ title: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, minHeight: 46)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modulaGlass(in: Capsule(), interactive: true, specular: true)
        .accessibilityIdentifier(id)
    }

    private func boop() {
        cheer += 1
        guard motionOn else { return }
        hop = true
        Task { try? await Task.sleep(for: .milliseconds(260)); hop = false }
    }

    // MARK: Segments

    private func segmentBar(_ proxy: ScrollViewProxy) -> some View {
        ModulaGlassGroup(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(MolibooHubSegment.allCases.filter { $0 != .studio }) { s in
                        Button { pick(s, proxy) } label: {
                            Label(s.title, systemImage: s.icon)
                                .labelStyle(.titleAndIcon)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .fixedSize()
                                .foregroundStyle(segment == s ? Color.white : Color.primary)
                                .padding(.horizontal, 14)
                                .frame(minHeight: 40)
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
            }
            .modulaHorizontalEdgeFade(12)
            .modulaGlass(in: Capsule(), interactive: false, specular: true)
        }
    }

    private func pick(_ s: MolibooHubSegment, _ proxy: ScrollViewProxy) {
        withAnimation(motionOn ? .spring(response: 0.38, dampingFraction: 0.78) : nil) { segment = s }
        HapticEngine.shared.play(.selection)
        switch s {
        case .collection: withAnimation { proxy.scrollTo("hub.grid", anchor: .top) }
        case .settings: withAnimation { proxy.scrollTo("hub.show", anchor: .top) }
        case .originals:
            segment = .collection
            withAnimation { proxy.scrollTo("hub.originals", anchor: .top) }
        case .studio:
            if native3D, let d = MolibooRegistry.descriptor(for: kindRaw) { route = .studio3D(d.id) } else { route = .studio(.wardrobe) }
            segment = .collection
        }
    }

    // MARK: Sheet

    private var collectionSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            collectionHeader.id("hub.grid")
            if searching {
                ModulaGlassSearchField(prompt: "Search Moliboos", text: $search)
            }
            ForEach(MolibooFamily.allCases) { fam in
                let ks = kinds.filter { $0.family == fam }
                if !ks.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fam.name).font(.headline)
                            Text("\(fam.world) · \(ks.count)").font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityAddTraits(.isHeader)
                        LazyVGrid(columns: grid, spacing: 14) {
                            ForEach(ks) { k in characterCard(k) }
                        }
                    }
                }
            }
            HStack(spacing: 12) {
                offCard.frame(maxWidth: .infinity)
                createCard.frame(maxWidth: .infinity)
            }
            .frame(height: 88)

            sectionTitle("The Originals").id("hub.originals")
            originals
            Text("25 founding Moliboos. Collect them as they arrive.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 26) {
            if kind != nil {
                settingsGroup("Show Moliboo on", footer: "Your Moliboo appears next to these inputs. On Home it walks along the bottom, peeks over posts and naps when idle.") {
                    toggleRow("bubble.left.and.text.bubble.right.fill", .purple, "Nodus", "Your AI companion", $nodus, "moliboo.hub.show.nodus")
                    rowDivider
                    toggleRow("text.bubble.fill", .blue, "Comment inputs", "Chats & comments", $comments, "moliboo.hub.show.comments")
                    rowDivider
                    toggleRow("pencil.line", .teal, "Other composers", "Posts, notes and more", $other, "moliboo.hub.show.other")
                    rowDivider
                    toggleRow("house.fill", .orange, "Home companion", "Walks along Home", $homeCompanion, "moliboo.hub.show.home")
                }
                .id("hub.show")
            } else {
                Color.clear.frame(height: 0).id("hub.show")
            }

            settingsGroup("Profile", footer: nil) {
                toggleRow("person.crop.circle.fill", .indigo, "Show on Profile", "With its scene", $showOnProfile, "moliboo.hub.profile.show")
                rowDivider
                toggleRow("person.crop.square.fill", .pink, "Use as avatar", "Long-press for wardrobe", $asAvatar, "moliboo.hub.profile.avatar")
            }

            settingsGroup("Motion & feel", footer: reduceMotion ? "Reduce Motion is on, so Moliboos stay calm." : nil) {
                toggleRow("figure.dance", .orange, "Playful animations", "Hops & celebrations", $playful, "moliboo.hub.playful")
                rowDivider
                toggleRow("hand.tap.fill", .purple, "Haptics", "Little taps", $haptics, "moliboo.hub.haptics")
                rowDivider
                toggleRow("speaker.wave.2.fill", .green, "Moliboo sounds", "Follows the silent switch", $sounds, "moliboo.hub.sounds")
                #if DEBUG
                rowDivider
                toggleRow("crown.fill", .yellow, "Unlock Premium", "Debug: preview every cosmetic", $debugPremium, "moliboo.hub.debugPremium")
                #endif
            }

            Button { showOnboarding = true } label: {
                Label("Replay the welcome", systemImage: "party.popper.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .modulaGlass(in: Capsule(), interactive: true, specular: true)
            .accessibilityIdentifier("moliboo.hub.replay")
        }
    }

    /// Inset-grouped section (Settings-app style): small caps header, one rounded surface, optional footer.
    private func settingsGroup<C: View>(_ title: String, footer: String?, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 16)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content() }
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
        }
    }

    private var rowDivider: some View {
        Divider().padding(.leading, 60)
    }

    private func toggleRow(_ icon: String, _ c: Color, _ title: String, _ sub: String, _ on: Binding<Bool>, _ id: String) -> some View {
        Toggle(isOn: on) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(c.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.body).foregroundStyle(.primary)
                    Text(sub).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .tint(.accentColor)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 60)
        .accessibilityIdentifier(id)
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
        let has3D = MolibooRegistry.has3D(k.rawValue)
        return Button {
            if locked { premiumKind = k; HapticEngine.shared.play(.warning); return }
            withAnimation(motionOn ? .spring(response: 0.4, dampingFraction: 0.72) : nil) { kindRaw = k.rawValue }
            MascotSound.shared.play(.pick)
            HapticEngine.shared.play(.selection)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(colors: [k.palette.light, k.palette.mid.opacity(0.82)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay {
                            MolibooHubArt(kind: k, size: 108)
                                .padding(8)
                        }
                        .frame(height: 132)
                    HStack(spacing: 4) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(Color(red: 0.21, green: 0.61, blue: 0.67), in: Circle())
                        }
                        if has3D && native3D {
                            Text("3D")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(Color(red: 0.21, green: 0.61, blue: 0.67)))
                        }
                        if k.isPremium {
                            Image(systemName: locked ? "lock.fill" : "crown.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(5)
                        }
                    }
                    .padding(8)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(k.name).font(.subheadline.weight(.bold)).foregroundStyle(.primary).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(String(format: "#%03d", k.number))
                        .font(.caption2.weight(.bold).monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(k.shortPersonality)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(minHeight: 28, alignment: .topLeading)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground)))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(selected ? Color(red: 0.21, green: 0.61, blue: 0.67) : Color.primary.opacity(0.06), lineWidth: selected ? 1.5 : 0.5))
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
            VStack(spacing: 6) {
                Image(systemName: "plus").font(.headline).foregroundStyle(.white).frame(width: 30, height: 30).background(Circle().fill(Color.blue.opacity(0.85)))
                Text("Create").font(.footnote.weight(.bold)).foregroundStyle(.blue)
                Text("Custom").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.blue.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.blue.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
        .buttonStyle(MolibooSpringPress(enabled: motionOn))
        .accessibilityIdentifier("moliboo.hub.create")
        .accessibilityLabel("Create custom Moliboo")
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s).font(.headline).padding(.top, 4)
    }

    private var originals: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(MolibooCosmetics.originals.enumerated()), id: \.offset) { i, id in
                    let k = ModulaMascotKind(rawValue: id)
                    Button { if k != nil { kindRaw = id } } label: {
                        VStack(spacing: 3) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LinearGradient(colors: [k?.palette.light ?? .gray, (k?.palette.mid ?? .gray).opacity(0.8)], startPoint: .top, endPoint: .bottom))
                                if native3D, let img = MolibooPortrait.image(for: id) { Image(uiImage: img).resizable().interpolation(.high).scaledToFit().padding(4).molibooPortraitEdge() }
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
    /// When shown inside the World, the chosen hero shares this namespace with the World's stage figure, so dismissing
    /// morphs the welcome hero straight into the pedestal (true matched-geometry morph across the two screens).
    var heroNS: Namespace.ID? = nil
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
                MoliboosWordmark(height: 44, onDark: true)
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
                // Feathered platform glow (was clipped to a hard-edged oval).
                Ellipse().fill(Color(red: 0.6, green: 0.9, blue: 1).opacity(0.38))
                    .frame(width: 260, height: 54)
                    .blur(radius: 18)
                    .offset(y: 86)
                if launching {
                    art(hero).matchedGeometryEffect(id: hero, in: morph).frame(width: 190, height: 190)
                        .modifier(MolibooHeroMorph(ns: heroNS))
                } else {
                    ForEach(Array(trio.enumerated()), id: \.element) { i, id in
                        let center = i == 1
                        art(id)
                            .matchedGeometryEffect(id: id, in: morph)
                            .frame(width: center ? 136 : 100, height: center ? 136 : 100)
                            // Grounded: a soft contact shadow under each pet that tightens as it bobs up.
                            .background(alignment: .bottom) {
                                Ellipse().fill(Color.black.opacity(0.32))
                                    .frame(width: (center ? 86 : 62) * (bob ? 0.9 : 1), height: 12)
                                    .blur(radius: 5)
                                    .offset(y: 6 + (bob ? 6 : -4) * (i == 1 ? 1 : 0.7))
                            }
                            .offset(x: CGFloat(i - 1) * w * 0.3 + CGFloat(page - 1) * -10 * CGFloat(i - 1),
                                    y: (center ? 4 : 24) + (bob ? -6 : 4) * (i == 1 ? 1 : 0.7))
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
            Image(systemName: p.2).font(.title3.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.pink.opacity(0.85), in: Circle())
                .frame(maxWidth: .infinity)
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
        if heroNS != nil {   // World: grow into the hero spot, then hand the figure to the World stage
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { launching = true }
            Task { try? await Task.sleep(for: .milliseconds(420)); withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) { done() } }
            return
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { launching = true }
        Task { try? await Task.sleep(for: .milliseconds(650)); done() }
    }
}

struct MolibooHeroMorph: ViewModifier {
    let ns: Namespace.ID?
    func body(content: Content) -> some View {
        if let ns { content.matchedGeometryEffect(id: "moliboo.hero", in: ns) } else { content }
    }
}


/// Progressive blur strip for pinned glass top bars: strongest under the status bar, fading to
/// nothing below the buttons. Light tint only, so the scene stays visible.
struct MolibooProgressiveStrip: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        // Solid wash — no Material. Material + mask on a pinned header re-composites every scroll frame.
        Rectangle()
            .fill(Color(uiColor: .systemBackground).opacity(scheme == .dark ? 0.94 : 0.92))
        .mask(LinearGradient(stops: [
            .init(color: .black, location: 0),
            .init(color: .black, location: 0.62),
            .init(color: .clear, location: 1)
        ], startPoint: .top, endPoint: .bottom))
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
