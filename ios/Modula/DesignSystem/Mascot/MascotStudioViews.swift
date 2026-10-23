import SwiftUI
import UIKit

// MARK: - Shared dressed renderers (stock or custom, same outfit everywhere)

/// Static dressed figure for any selection.
struct MascotDressedFigure: View {
    let selection: MascotSelection
    var size: CGFloat
    var outfit: MascotOutfit
    var pose: MascotPose = .still(.happy)

    var body: some View {
        switch selection {
        case .stock(let k): ModulaMascotFigure(kind: k, pose: pose, size: size, outfit: outfit)
        case .custom(let c): CustomMascotFigure(mascot: c, pose: pose, size: size, outfit: outfit)
        case .off: ModulaMascotFigure(kind: .pip, pose: pose, size: size, outfit: outfit)
        }
    }
}

/// Live (brain-driven) dressed mascot for any selection.
struct MascotDressedLive: View {
    let selection: MascotSelection
    var size: CGFloat
    var brain: MascotBrain
    var showsShadow = true
    var animated = true
    var outfit: MascotOutfit

    var body: some View {
        switch selection {
        case .stock(let k):
            ModulaLiveMascot(kind: k, size: size, brain: brain, showsShadow: showsShadow, animated: animated, bubble: false, outfit: outfit)
        case .custom(let c):
            CustomLiveMascot(mascot: c, size: size, brain: brain, showsShadow: showsShadow, animated: animated, outfit: outfit)
        case .off:
            ModulaLiveMascot(kind: .pip, size: size, brain: brain, showsShadow: showsShadow, animated: animated, bubble: false, outfit: outfit)
        }
    }
}

// MARK: - Mascot Studio

struct MascotStudioView: View {
    var initialTab: StudioTab = .wardrobe
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    @State private var tab: StudioTab = .wardrobe
    @State private var slot: MascotWardrobeSlot = .hat
    @State private var brain = MascotBrain()
    @State private var editingCustom: CustomMascot?
    @State private var detailItem: MascotWardrobeItem?
    @State private var showClearConfirm = false
    @State private var fitsOnly = false
    @State private var ownedOnly = false
    @State private var naming = false
    @State private var presetName = ""
    @State private var renaming: MascotOutfitPreset?
    @State private var shareImage: ShareableImage?
    @State private var toast: String?
    @State private var sparkleTick = 0
    @State private var rotation: Double = 0
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var chestReward: MascotChestReward?
    @State private var didAppear = false
    private var wardrobe = MascotWardrobeStore.shared
    private var progress = MascotProgressStore.shared
    private var customs = CustomMascotStore.shared

    /// Embedded inside the one Living Studio ("More" panel): no preview, no own background/title, no 3D entry.
    var embedded = false

    init(initialTab: StudioTab = .wardrobe, embedded: Bool = false) {
        self.initialTab = initialTab
        self.embedded = embedded
    }

    enum StudioTab: String, CaseIterable, Identifiable {
        case wardrobe, rewards, custom, assistant
        var id: String { rawValue }
        var title: String {
            switch self {
            case .wardrobe: "Wardrobe"
            case .rewards: "Rewards"
            case .custom: "Custom"
            case .assistant: "Assistant"
            }
        }
    }

    private var selection: MascotSelection { MascotSelection.resolve(raw: kindRaw) }
    private var rig: MascotRig { selection.rig }

    /// Tabs shown: embedded in the 3D Studio, its own Wardrobe panel covers wardrobe, so only the rest appear here.
    private var tabs: [StudioTab] { embedded ? [.rewards, .custom, .assistant] : StudioTab.allCases }

    var body: some View {
        if embedded { embeddedBody } else { standaloneBody }
    }

    /// Coins, rewards, custom Moliboos, the assistant and the outfit actions (shuffle / save / share / clear / undo),
    /// as a section of the single Studio.
    private var embeddedBody: some View {
        VStack(spacing: 14) {
            HStack { Spacer(); coinPill }
            actionBar
            // Stacked sections, no inner tabs: the Studio sheet's segmented control is the only tab level.
            embeddedSection("Rewards", "gift.fill") { rewardsPanel }
            if tabs.contains(.custom) { embeddedSection("Custom Moliboos", "wand.and.stars") { customPanel } }
            if tabs.contains(.assistant) { embeddedSection("Assistant", "bubble.left.and.text.bubble.right.fill") { MascotAssistantSettingsSection() } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("studio.more")
        .onAppear {
            guard !didAppear else { return }
            didAppear = true
            tab = tabs.contains(initialTab) ? initialTab : .rewards
            progress.touchDay()
        }
    }

    private func embeddedSection<C: View>(_ title: String, _ symbol: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.headline).accessibilityAddTraits(.isHeader)
            c()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var standaloneBody: some View {
        ScrollView {
            VStack(spacing: 16) {
                previewCard
                actionBar
                Picker("Studio", selection: $tab) {
                    ForEach(StudioTab.allCases) { t in Text(t.title).tag(t) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 2)

                switch tab {
                case .wardrobe: wardrobePanel
                case .rewards: rewardsPanel
                case .custom: customPanel
                case .assistant: MascotAssistantSettingsSection()
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Moliboo Studio")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { coinPill }
        }
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .modulaGlass(in: Capsule(), interactive: false)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            guard !didAppear else { return }
            didAppear = true
            tab = initialTab
            progress.touchDay()
            _ = wardrobe.applyOutfitOfTheDayIfNeeded()
            _ = wardrobe.applyBirthdayOutfitIfNeeded(birthday: MascotAssistantStore.shared.context.birthday)
            brain.react(.happy)
        }
        .onChange(of: progress.lastUnlocked) { _, unlocked in
            guard let unlocked else { return }
            showToast("Unlocked: \(unlocked.title)")
            brain.celebrate()
            progress.lastUnlocked = nil
        }
        .sheet(item: $editingCustom) { draft in
            NavigationStack {
                CustomMascotEditor(mascot: draft) { saved in
                    _ = customs.save(saved)
                    kindRaw = saved.id
                    editingCustom = nil
                    brain.react(.excited)
                    brain.burst(.confetti)
                }
            }
        }
        .sheet(item: $detailItem) { item in
            MascotItemDetailSheet(item: item, selection: selection) { equipped in
                if equipped { celebrateEquip() }
            }
        }
        .sheet(item: $shareImage) { img in
            MascotActivitySheet(items: [img.image])
                .presentationDetents([.medium, .large])
        }
        .alert("Save outfit", isPresented: $naming) {
            TextField("Name", text: $presetName)
            Button("Save") {
                wardrobe.savePreset(named: presetName)
                presetName = ""
                showToast("Outfit saved")
            }
            Button("Cancel", role: .cancel) { presetName = "" }
        }
        .alert("Rename outfit", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $presetName)
            Button("Save") {
                if let renaming { wardrobe.renamePreset(renaming, to: presetName) }
                presetName = ""
                renaming = nil
            }
            Button("Cancel", role: .cancel) { presetName = ""; renaming = nil }
        }
        .confirmationDialog("Clear outfit?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear outfit", role: .destructive) {
                wardrobe.clearOutfit()
                brain.react(.surprised)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Preview

    private var coinPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.hexagongrid.fill").foregroundStyle(.yellow)
            Text("\(progress.coins)").font(.subheadline.weight(.bold)).monospacedDigit()
                .contentTransition(.numericText())
        }
        .animation(.snappy, value: progress.coins)
        .accessibilityLabel("\(progress.coins) coins")
    }

    private var previewCard: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        return VStack(spacing: 10) {
            ZStack {
                if let bg = wardrobe.outfit.background {
                    MascotSceneView(item: bg, dye: wardrobe.outfit.color(for: .background), animated: true)
                        .clipShape(shape)
                } else {
                    shape.fill(LinearGradient(colors: [selection.accent.opacity(0.4), Color.primary.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                livePreview
                    .scaleEffect(zoom)
                    .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                    .offset(y: 10)
                SparkleBurst(trigger: sparkleTick)
                    .allowsHitTesting(false)
            }
            .frame(height: 230)
            .clipShape(shape)
            .contentShape(shape)
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { v in rotation = max(-40, min(40, Double(v.translation.width) / 3)) }
                    .onEnded { _ in withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { rotation = 0 } }
                    .simultaneously(with:
                        MagnifyGesture()
                            .onChanged { v in zoom = max(0.8, min(1.8, baseZoom * v.magnification)) }
                            .onEnded { _ in baseZoom = zoom }
                    )
            )
            .onTapGesture(count: 2) { withAnimation(.spring) { zoom = 1; baseZoom = 1 } }
            .onTapGesture { brain.hop(burst: .sparkle); MascotSound.shared.play(.hop) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(selection.displayName) wearing \(outfitDescription)")
            .accessibilityHint("Pinch to zoom, tap to hop.")

            HStack(spacing: 8) {
                ForEach(Emote.allCases) { e in
                    Button {
                        play(e)
                    } label: {
                        Label(e.title, systemImage: e.symbol)
                            .labelStyle(.iconOnly)
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 38, height: 34)
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: Capsule(), interactive: true)
                    .accessibilityLabel(e.title)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(selection.displayName).font(.headline)
                    Text("\(wardrobe.outfit.items.count) item\(wardrobe.outfit.items.count == 1 ? "" : "s") on")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .modulaGlass(in: shape, interactive: false)
    }

    private var outfitDescription: String {
        let names = MascotWardrobeSlot.allCases.compactMap { wardrobe.outfit.item(for: $0)?.name }
        return names.isEmpty ? "nothing" : names.joined(separator: ", ")
    }

    @ViewBuilder private var livePreview: some View {
        if case .off = selection {
            ContentUnavailableView("Moliboo off", systemImage: "eye.slash", description: Text("Pick a Moliboo in Settings → Moliboo."))
        } else {
            MascotDressedLive(selection: selection, size: 84, brain: brain, outfit: wardrobe.outfit)
        }
    }

    private enum Emote: String, CaseIterable, Identifiable {
        case wave, dance, sit, celebrate
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var symbol: String {
            switch self {
            case .wave: "hand.wave.fill"
            case .dance: "music.note"
            case .sit: "chair.lounge.fill"
            case .celebrate: "party.popper.fill"
            }
        }
    }

    private func play(_ e: Emote) {
        switch e {
        case .wave: brain.wave()
        case .dance: brain.dance()
        case .sit: brain.sit()
        case .celebrate: brain.celebrate()
        }
        MascotSound.shared.play(.pick)
        HapticEngine.shared.play(.selection)
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            actionButton("Undo", "arrow.uturn.backward", disabled: !wardrobe.canUndo) { wardrobe.undo(); brain.react(.pleased) }
            actionButton("Shuffle", "dice.fill") {
                wardrobe.randomize(for: rig)
                celebrateEquip()
            }
            actionButton("Save", "square.and.arrow.down.on.square", disabled: wardrobe.outfit.isEmpty) { presetName = ""; naming = true }
            actionButton("Share", "square.and.arrow.up") { share() }
            actionButton("Clear", "xmark.circle", disabled: wardrobe.outfit.isEmpty) { showClearConfirm = true }
        }
    }

    private func actionButton(_ title: String, _ symbol: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            action()
            HapticEngine.shared.play(.selection)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                Text(title).font(.caption2.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 46)
        }
        .buttonStyle(.plain)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
        .opacity(disabled ? 0.4 : 1)
        .disabled(disabled)
    }

    private func celebrateEquip() {
        sparkleTick += 1
        brain.outfitChanged()
        MascotSound.shared.play(.pick)
    }

    private func showToast(_ text: String) {
        ModulaToastCenter.shared.show(text, symbol: "sparkles", tone: .info)
    }

    private func share() {
        let card = MascotShareCard(selection: selection, outfit: wardrobe.outfit)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let image = renderer.uiImage {
            shareImage = ShareableImage(image: image)
        }
    }

    // MARK: Wardrobe panel

    private var wardrobePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            slotChips
            HStack(spacing: 8) {
                filterChip("Fits \(selection.displayName)", on: $fitsOnly, symbol: "checkmark.seal")
                filterChip("Owned", on: $ownedOnly, symbol: "bag")
                Spacer()
                let owned = progress.ownedCount(in: slot)
                let total = MascotWardrobeCatalog.items(in: slot).count
                Text("\(owned)/\(total)").font(.caption.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
            }
            if !wardrobe.presets.isEmpty { presetsRow }

            let items = filteredItems
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                noneTile
                ForEach(items) { item in
                    MascotItemTile(item: item, selection: selection, rig: rig, outfit: wardrobe.outfit, owned: wardrobe.owns(item)) {
                        tap(item)
                    } onLongPress: {
                        detailItem = item
                        HapticEngine.shared.play(.contextOpen)
                    }
                }
            }
            if items.isEmpty {
                Text(fitsOnly ? "Nothing in \(slot.title.lowercased()) fits \(selection.displayName) with these filters." : "Nothing here yet.")
                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            Text("\(MascotWardrobeCatalog.all.count) items · \(MascotWardrobeCatalog.freeCount) free · \(MascotWardrobeCatalog.earnableCount) earnable · \(MascotWardrobeCatalog.premiumCount) Premium. Hold an item for details and colours.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var filteredItems: [MascotWardrobeItem] {
        MascotWardrobeCatalog.items(in: slot).filter { item in
            (!fitsOnly || item.fit(on: rig).isWearable) && (!ownedOnly || wardrobe.owns(item))
        }
    }

    private var slotChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MascotWardrobeSlot.allCases) { s in
                    let on = slot == s
                    Button {
                        withAnimation(.snappy) { slot = s }
                        HapticEngine.shared.play(.selection)
                    } label: {
                        VStack(spacing: 4) {
                            Label(s.title, systemImage: s.symbol)
                                .font(.caption.weight(.semibold))
                            ProgressView(value: progress.collectionFraction(s))
                                .progressViewStyle(.linear)
                                .tint(on ? Color.accentColor : .secondary)
                                .frame(width: 54)
                                .scaleEffect(y: 0.6)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: Capsule(), interactive: true)
                    .overlay(Capsule().strokeBorder(on ? Color.accentColor : .clear, lineWidth: 1.5))
                    .opacity(on ? 1 : 0.78)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func filterChip(_ title: String, on: Binding<Bool>, symbol: String) -> some View {
        Button {
            on.wrappedValue.toggle()
            HapticEngine.shared.play(.selection)
        } label: {
            Label(title, systemImage: on.wrappedValue ? "\(symbol).fill" : symbol)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(Capsule().fill(on.wrappedValue ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05)))
        .overlay(Capsule().strokeBorder(on.wrappedValue ? Color.accentColor : .clear, lineWidth: 1))
    }

    private var presetsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Saved outfits").font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(wardrobe.presets) { preset in
                        Button {
                            wardrobe.applyPreset(preset)
                            celebrateEquip()
                        } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    if let bg = preset.outfit.background {
                                        MascotSceneView(item: bg, dye: preset.outfit.color(for: .background))
                                    }
                                    MascotDressedFigure(selection: selection, size: 30, outfit: preset.outfit)
                                }
                                .frame(width: 70, height: 62)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                Text(preset.name).font(.caption2.weight(.semibold)).lineLimit(1).frame(width: 70)
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(preset.outfit == wardrobe.outfit ? 0.1 : 0.04)))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Apply", systemImage: "tshirt") { wardrobe.applyPreset(preset); celebrateEquip() }
                            Button("Rename", systemImage: "pencil") { presetName = preset.name; renaming = preset }
                            Button("Delete", systemImage: "trash", role: .destructive) { wardrobe.deletePreset(preset) }
                        }
                    }
                }
            }
        }
    }

    private var noneTile: some View {
        let empty = wardrobe.outfit.item(for: slot) == nil
        return Button {
            wardrobe.unequip(slot)
            brain.react(.pleased)
            HapticEngine.shared.play(.selection)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "slash.circle").font(.title2).foregroundStyle(.secondary).frame(height: 62)
                Text("None").font(.caption.weight(.semibold))
                Text(" ").font(.caption2)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 118)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(empty ? 0.08 : 0.03)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(empty ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("No \(slot.title.lowercased())")
    }

    private func tap(_ item: MascotWardrobeItem) {
        let fit = item.fit(on: rig)
        guard fit.isWearable else {
            showToast("\(item.name) doesn’t fit \(selection.displayName)")
            brain.react(.shy)
            HapticEngine.shared.play(.warning)
            return
        }
        guard wardrobe.canEquip(item) else {
            detailItem = item
            HapticEngine.shared.play(.warning)
            return
        }
        if wardrobe.outfit.contains(item) {
            wardrobe.unequip(item.slot)
            brain.react(.pleased)
        } else {
            wardrobe.equip(item)
            celebrateEquip()
            if case .adapted(let note) = fit { showToast(note) }
        }
        HapticEngine.shared.play(.selection)
    }

    // MARK: Rewards panel

    private var rewardsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            chestCard
            VStack(alignment: .leading, spacing: 8) {
                Text("Achievements").font(.headline)
                ForEach(MascotAchievement.all) { a in
                    let p = progress.progress(for: a)
                    let done = progress.isUnlocked(a)
                    HStack(spacing: 12) {
                        Image(systemName: a.symbol)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(done ? .white : .secondary)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(done ? AnyShapeStyle(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.primary.opacity(0.06))))
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(a.title).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(done ? "Done" : "\(p.value)/\(p.goal)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            Text(a.detail).font(.caption).foregroundStyle(.secondary)
                            ProgressView(value: Double(p.value), total: Double(max(p.goal, 1))).tint(done ? .green : .accentColor)
                            HStack(spacing: 6) {
                                if let id = a.rewardItemID, let item = MascotWardrobeCatalog.item(id: id) {
                                    Label(item.name, systemImage: "gift.fill").font(.caption2.weight(.semibold)).foregroundStyle(item.rarity.color)
                                }
                                Label("\(a.rewardCoins)", systemImage: "circle.hexagongrid.fill").font(.caption2.weight(.semibold)).foregroundStyle(.yellow)
                            }
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.04)))
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Collection").font(.headline)
                ForEach(MascotWardrobeSlot.allCases) { s in
                    HStack {
                        Label(s.title, systemImage: s.symbol).font(.subheadline).frame(width: 130, alignment: .leading)
                        ProgressView(value: progress.collectionFraction(s))
                        Text("\(progress.ownedCount(in: s))/\(MascotWardrobeCatalog.items(in: s).count)")
                            .font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.03)))
            shopSection
        }
    }

    private var chestCard: some View {
        HStack(spacing: 14) {
            Image(systemName: progress.canOpenChest ? "shippingbox.fill" : "shippingbox")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                .symbolEffect(.bounce, value: progress.canOpenChest)
                .frame(width: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text("Daily chest").font(.headline)
                if let r = chestReward {
                    Text(rewardText(r)).font(.caption.weight(.medium)).foregroundStyle(Color.primary.opacity(0.75))
                } else {
                    Text(progress.canOpenChest ? "Coins and the odd item. Streak: \(progress.streak) day\(progress.streak == 1 ? "" : "s")." : "Come back tomorrow. Streak: \(progress.streak) day\(progress.streak == 1 ? "" : "s").")
                        .font(.caption.weight(.medium)).foregroundStyle(Color.primary.opacity(0.75))
                }
            }
            Spacer()
            Button("Open") {
                if let r = progress.openChest() {
                    withAnimation(.spring) { chestReward = r }
                    brain.celebrate()
                    sparkleTick += 1
                    HapticEngine.shared.play(.success)
                    MascotSound.shared.play(.send)
                }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(!progress.canOpenChest)
        }
        .padding(14)
        // Solid-enough card so the copy reads over any stage background.
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.85), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .modulaGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous), interactive: false)
    }

    private func rewardText(_ r: MascotChestReward) -> String {
        if let id = r.itemID, let item = MascotWardrobeCatalog.item(id: id) { return "+\(r.coins) coins and \(item.name)!" }
        return "+\(r.coins) coins"
    }

    private var shopSection: some View {
        let forSale = MascotWardrobeCatalog.all.filter { $0.coinPrice != nil && !wardrobe.owns($0) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Coin shop").font(.headline)
                Spacer()
                Text("Earn coins by commenting, reacting and opening chests.").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
            if forSale.isEmpty {
                Text("You own everything in the shop.").font(.footnote).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                ForEach(forSale) { item in
                    MascotItemTile(item: item, selection: selection, rig: rig, outfit: wardrobe.outfit, owned: false) {
                        detailItem = item
                    } onLongPress: {
                        detailItem = item
                    }
                }
            }
            #if DEBUG
            HStack {
                Button("+500 coins (Debug)") { progress.debugAddCoins(500) }
                Button("Reset progress (Debug)", role: .destructive) { progress.debugReset() }
            }
            .font(.caption)
            .buttonStyle(.bordered)
            #endif
        }
    }

    // MARK: Custom panel

    private var customPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create up to \(CustomMascotStore.maxCount) custom Moliboos. They stay on this device and wear the same wardrobe.")
                .font(.caption).foregroundStyle(.secondary)

            ForEach(customs.items) { custom in
                HStack(spacing: 12) {
                    CustomMascotFigure(mascot: custom, pose: .still(.happy), size: 34, outfit: kindRaw == custom.id ? wardrobe.outfit : .empty)
                        .frame(width: 64, height: 60)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(custom.name).font(.subheadline.weight(.semibold))
                        Text(custom.personality).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    if kindRaw == custom.id {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(kindRaw == custom.id ? 0.08 : 0.03)))
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Use", systemImage: "checkmark") { kindRaw = custom.id; brain.react(.happy) }
                    Button("Edit", systemImage: "pencil") { editingCustom = custom }
                    Button("Delete", systemImage: "trash", role: .destructive) { customs.delete(id: custom.id) }
                }
                .onTapGesture { kindRaw = custom.id; brain.react(.happy); MascotSound.shared.play(.pick) }
            }

            Button {
                guard customs.items.count < CustomMascotStore.maxCount else { return }
                editingCustom = .fresh()
            } label: {
                Label(customs.items.count >= CustomMascotStore.maxCount ? "Limit reached" : "Create custom Moliboo", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(customs.items.count >= CustomMascotStore.maxCount)
        }
    }
}

// MARK: - Item tile

struct MascotItemTile: View {
    let item: MascotWardrobeItem
    let selection: MascotSelection
    let rig: MascotRig
    let outfit: MascotOutfit
    let owned: Bool
    var onTap: () -> Void
    var onLongPress: () -> Void

    var body: some View {
        let fit = item.fit(on: rig)
        let equipped = outfit.contains(item)
        let inSeason = item.isAvailable()
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let dye = equipped ? outfit.dye(for: item.slot) : 0
        VStack(spacing: 4) {
            ZStack {
                if item.slot == .background {
                    MascotSceneView(item: item, dye: item.dye(dye))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                MascotDressedFigure(selection: selection, size: 32, outfit: .solo(item, dye: dye))
                    .frame(width: 80, height: 62)
                    .clipped()
                    .saturation(fit.isWearable ? 1 : 0.2)
            }
            .frame(height: 62)
            Text(item.name).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            statusLine(fit: fit, inSeason: inSeason)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 118)
        .background(shape.fill(LinearGradient(colors: [item.rarity.color.opacity(equipped ? 0.24 : 0.12), Color.primary.opacity(0.03)], startPoint: .top, endPoint: .bottom)))
        .overlay(shape.strokeBorder(equipped ? Color.accentColor : item.rarity.color.opacity(0.75), lineWidth: equipped ? 2.5 : (item.rarity.glows ? 1.6 : 1)))
        .shadow(color: item.rarity.glows ? item.rarity.color.opacity(item.rarity == .legendary ? 0.55 : 0.35) : .clear, radius: item.rarity == .legendary ? 8 : 5)
        .overlay(alignment: .topTrailing) { badge(equipped: equipped, inSeason: inSeason) }
        .overlay(alignment: .topLeading) {
            if item.isPremium {
                Image(systemName: "crown.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.orange).padding(7)
            }
        }
        .opacity(fit.isWearable ? 1 : 0.5)
        .contentShape(shape)
        .onTapGesture(perform: onTap)
        .onLongPressGesture(minimumDuration: 0.35, perform: onLongPress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(fit: fit, equipped: equipped, inSeason: inSeason))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(equipped ? .isSelected : [])
        .accessibilityAction(named: "Details", onLongPress)
    }

    @ViewBuilder private func statusLine(fit: MascotFit, inSeason: Bool) -> some View {
        if case .none = fit {
            Text("Doesn’t fit").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        } else if case .adapted = fit {
            Text("Adapts").font(.caption2.weight(.semibold)).foregroundStyle(.teal)
        } else if !inSeason, let season = item.seasonLabel {
            Text(season).font(.caption2).foregroundStyle(.secondary)
        } else if !owned, let price = item.coinPrice {
            Label("\(price)", systemImage: "circle.hexagongrid.fill").font(.caption2.weight(.semibold)).foregroundStyle(.yellow)
        } else if !owned, item.achievementID != nil {
            Label("Earn", systemImage: "trophy.fill").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
        } else if !owned, item.isPremium {
            Text("Premium").font(.caption2.weight(.semibold)).foregroundStyle(.orange)
        } else {
            Text(item.rarity.title).font(.caption2.weight(.semibold)).foregroundStyle(item.rarity.color)
        }
    }

    @ViewBuilder private func badge(equipped: Bool, inSeason: Bool) -> some View {
        if equipped {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .bold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.green)
                .padding(5)
                .transition(.scale.combined(with: .opacity))
        } else if !inSeason {
            Image(systemName: "calendar").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                .frame(width: 18, height: 18).background(Circle().fill(Color.secondary)).padding(6)
        } else if !owned {
            Image(systemName: item.coinPrice != nil ? "circle.hexagongrid.fill" : (item.achievementID != nil ? "trophy.fill" : "lock.fill"))
                .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom)))
                .padding(6)
        }
    }

    private func accessibilityText(fit: MascotFit, equipped: Bool, inSeason: Bool) -> String {
        var parts = [item.name, item.rarity.title]
        if equipped { parts.append("equipped") }
        if let label = fit.label { parts.append(label) }
        if !inSeason { parts.append("out of season") }
        if !owned {
            if let p = item.coinPrice { parts.append("\(p) coins") } else if item.achievementID != nil { parts.append("earned by an achievement") } else if item.isPremium { parts.append("Premium") }
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Item detail sheet

struct MascotItemDetailSheet: View {
    let item: MascotWardrobeItem
    let selection: MascotSelection
    var onEquip: (Bool) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var dye = 0
    @State private var brain = MascotBrain()
    @State private var message: String?
    private var wardrobe = MascotWardrobeStore.shared
    private var progress = MascotProgressStore.shared

    init(item: MascotWardrobeItem, selection: MascotSelection, onEquip: @escaping (Bool) -> Void = { _ in }) {
        self.item = item
        self.selection = selection
        self.onEquip = onEquip
    }

    var body: some View {
        let rig = selection.rig
        let fit = item.fit(on: rig)
        let owned = wardrobe.owns(item)
        let preview: MascotOutfit = {
            var o = wardrobe.outfit
            if fit.isWearable { o.equip(item, dye: dye) }
            return o
        }()
        ScrollView {
            VStack(spacing: 14) {
                Capsule().fill(Color.secondary.opacity(0.35)).frame(width: 36, height: 5).padding(.top, 8)
                ZStack {
                    if let bg = preview.background {
                        MascotSceneView(item: bg, dye: preview.color(for: .background), animated: true)
                    } else {
                        LinearGradient(colors: [item.rarity.color.opacity(0.3), Color.primary.opacity(0.03)], startPoint: .top, endPoint: .bottom)
                    }
                    MascotDressedLive(selection: selection, size: 76, brain: brain, outfit: preview)
                }
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(item.rarity.color.opacity(0.8), lineWidth: 1.5))
                .shadow(color: item.rarity.glows ? item.rarity.color.opacity(0.4) : .clear, radius: 10)

                VStack(spacing: 6) {
                    Text(item.name).font(.title3.weight(.bold))
                    HStack(spacing: 6) {
                        chip(item.rarity.title, item.rarity.color)
                        chip(item.slot.title, .secondary)
                        if item.isPremium { MascotPremiumBadge(locked: !MascotEntitlements.isPremium) }
                        if let season = item.seasonLabel { chip(season, .teal) }
                    }
                    Text(item.blurb).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if let label = fit.label {
                        Label(label, systemImage: fit.isWearable ? "wand.and.stars" : "exclamationmark.triangle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(fit.isWearable ? .teal : .orange)
                    }
                }

                if item.dyes.count > 1 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Colours").font(.subheadline.weight(.semibold))
                        HStack(spacing: 10) {
                            ForEach(item.dyes.indices, id: \.self) { i in
                                Button {
                                    dye = i
                                    brain.react(.pleased)
                                    HapticEngine.shared.play(.selection)
                                } label: {
                                    Circle().fill(item.dyes[i])
                                        .frame(width: 30, height: 30)
                                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                                        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: dye == i ? 3 : 0).padding(-4))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Colour \(i + 1)")
                                .accessibilityAddTraits(dye == i ? .isSelected : [])
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let message { Text(message).font(.footnote.weight(.semibold)).foregroundStyle(.orange) }

                actions(owned: owned, fit: fit)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.thinMaterial)
        .onAppear {
            if wardrobe.outfit.contains(item) { dye = wardrobe.outfit.dye(for: item.slot) }
            brain.react(.curious)
        }
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.16)))
            .foregroundStyle(color)
    }

    @ViewBuilder private func actions(owned: Bool, fit: MascotFit) -> some View {
        VStack(spacing: 10) {
            if owned && item.isAvailable() {
                Button {
                    guard fit.isWearable else { return }
                    if wardrobe.outfit.contains(item) && wardrobe.outfit.dye(for: item.slot) == dye {
                        wardrobe.unequip(item.slot)
                        onEquip(false)
                    } else {
                        wardrobe.equip(item, dye: dye)
                        onEquip(true)
                    }
                    dismiss()
                } label: {
                    Text(wardrobe.outfit.contains(item) && wardrobe.outfit.dye(for: item.slot) == dye ? "Take off" : "Wear")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(!fit.isWearable)
            } else if !item.isAvailable() {
                Text("Back in season: \(item.seasonLabel ?? "")").font(.subheadline).foregroundStyle(.secondary)
            } else if let price = item.coinPrice {
                Button {
                    switch progress.buy(item) {
                    case .bought:
                        brain.celebrate()
                        HapticEngine.shared.play(.success)
                        if fit.isWearable { wardrobe.equip(item, dye: dye); onEquip(true) }
                        dismiss()
                    case .insufficient:
                        message = "You need \(price - progress.coins) more coins."
                        HapticEngine.shared.play(.warning)
                    default: break
                    }
                } label: {
                    Label("Buy for \(price)", systemImage: "circle.hexagongrid.fill")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.orange)
                Text("Balance: \(progress.coins) coins").font(.caption).foregroundStyle(.secondary)
            } else if let ach = item.achievementID, let a = MascotAchievement.with(id: ach) {
                let p = progress.progress(for: a)
                VStack(spacing: 6) {
                    Label("Unlock: \(a.title)", systemImage: a.symbol).font(.subheadline.weight(.semibold))
                    Text(a.detail).font(.caption).foregroundStyle(.secondary)
                    ProgressView(value: Double(p.value), total: Double(max(1, p.goal)))
                }
            } else if item.isPremium {
                VStack(spacing: 6) {
                    Text("Part of the Premium wardrobe.").font(.subheadline).foregroundStyle(.secondary)
                    Text("Premium unlocks with Modula Premium.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Button("Close") { dismiss() }.font(.subheadline.weight(.semibold))
        }
    }
}

/// Kept for callers of the old premium sheet: shows the detail sheet for the current mascot.
struct MascotWardrobePremiumSheet: View {
    let item: MascotWardrobeItem
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue

    var body: some View {
        MascotItemDetailSheet(item: item, selection: MascotSelection.resolve(raw: kindRaw))
    }
}

// MARK: - Sparkle burst on try-on

struct SparkleBurst: View {
    let trigger: Int
    @State private var start: Date = .distantPast

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: Date().timeIntervalSince(start) > 1.0)) { tl in
            let e = tl.date.timeIntervalSince(start)
            Canvas { ctx, size in
                guard e < 0.9 else { return }
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let k = e / 0.9
                for i in 0..<14 {
                    let a = Double(i) / 14 * 2 * .pi + Double(i % 3) * 0.2
                    let d = CGFloat(30 + 80 * k) * (i % 2 == 0 ? 1 : 0.7)
                    let p = CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d * 0.8)
                    let r = CGFloat(7 * (1 - k))
                    var s = Path()
                    s.move(to: CGPoint(x: p.x, y: p.y - r)); s.addQuadCurve(to: CGPoint(x: p.x + r, y: p.y), control: p)
                    s.addQuadCurve(to: CGPoint(x: p.x, y: p.y + r), control: p); s.addQuadCurve(to: CGPoint(x: p.x - r, y: p.y), control: p)
                    s.addQuadCurve(to: CGPoint(x: p.x, y: p.y - r), control: p)
                    ctx.fill(s, with: .color([Color.yellow, .white, .pink, .cyan][i % 4].opacity(1 - k)))
                }
            }
        }
        .onChange(of: trigger) { _, _ in start = Date() }
    }
}

// MARK: - Share card

struct ShareableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct MascotShareCard: View {
    let selection: MascotSelection
    let outfit: MascotOutfit

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                if let bg = outfit.background {
                    MascotSceneView(item: bg, dye: outfit.color(for: .background))
                } else {
                    LinearGradient(colors: [selection.accent, selection.accent.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                MascotDressedFigure(selection: selection, size: 120, outfit: outfit)
                    .offset(y: 14)
            }
            .frame(width: 320, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selection.displayName).font(.title2.weight(.heavy))
                    Text(itemsLine).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                ModulaWordmark(height: 16)
            }
            .padding(.horizontal, 6)
        }
        .padding(16)
        .frame(width: 352)
        .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(Color.white))
        .environment(\.colorScheme, .light)
    }

    private var itemsLine: String {
        let names = MascotWardrobeSlot.allCases.filter { $0 != .background }.compactMap { outfit.item(for: $0)?.name }
        return names.isEmpty ? "Just being themselves" : names.joined(separator: " · ")
    }
}

struct MascotActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Custom editor

struct CustomMascotEditor: View {
    @State var mascot: CustomMascot
    var onSave: (CustomMascot) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var brain = MascotBrain()
    private var wardrobe = MascotWardrobeStore.shared

    init(mascot: CustomMascot, onSave: @escaping (CustomMascot) -> Void) {
        _mascot = State(initialValue: mascot)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section {
                CustomLiveMascot(mascot: mascot, size: 64, brain: brain, outfit: wardrobe.outfit)
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } footer: {
                Text("Previewed in your current outfit. Items adapt to the body you choose.")
            }
            Section("Identity") {
                TextField("Name", text: $mascot.name)
                TextField("Personality", text: $mascot.personality, axis: .vertical)
                    .lineLimit(2...4)
                TextField("Catchphrase", text: $mascot.tic)
            }
            Section("Body") {
                Picker("Shape", selection: $mascot.shape) {
                    ForEach(MascotBodyShape.customChoices) { s in Text(s.title).tag(s.rawValue) }
                }
                Toggle("Little feet", isOn: $mascot.feet)
            }
            Section("Colours") {
                colorRow("Body", r: $mascot.bodyR, g: $mascot.bodyG, b: $mascot.bodyB)
                colorRow("Accent", r: $mascot.accentR, g: $mascot.accentG, b: $mascot.accentB)
                colorRow("Eyes", r: $mascot.irisR, g: $mascot.irisG, b: $mascot.irisB)
            }
            Section("Features") {
                Picker("Eyes", selection: $mascot.eyeStyle) {
                    Text("Round").tag("round"); Text("Happy").tag("happy"); Text("Sleepy").tag("sleepy")
                }
                Picker("Mouth", selection: $mascot.mouthStyle) {
                    Text("Smile").tag("smile"); Text("Open").tag("open"); Text("Cat").tag("cat"); Text("None").tag("none")
                }
                Picker("Ears", selection: $mascot.ears) {
                    Text("None").tag("none"); Text("Round").tag("round"); Text("Pointy").tag("pointy"); Text("Floppy").tag("floppy")
                }
                Picker("Extras", selection: $mascot.extras) {
                    Text("None").tag("none"); Text("Gills").tag("gills"); Text("Tail").tag("tail"); Text("Antenna").tag("antenna"); Text("Horns").tag("horns")
                }
            }
        }
        .navigationTitle("Custom Moliboo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(mascot)
                    dismiss()
                }
                .fontWeight(.semibold)
                .disabled(mascot.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onChange(of: mascot) { _, _ in brain.react(.pleased) }
    }

    private func colorRow(_ title: String, r: Binding<Double>, g: Binding<Double>, b: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Circle().fill(Color(red: r.wrappedValue, green: g.wrappedValue, blue: b.wrappedValue))
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
            }
            Slider(value: r, in: 0...1).tint(.red)
            Slider(value: g, in: 0...1).tint(.green)
            Slider(value: b, in: 0...1).tint(.blue)
        }
    }
}

// MARK: - Assistant settings section

struct MascotAssistantSettingsSection: View {
    private var store = MascotAssistantStore.shared
    @State private var newKeyword = ""
    @State private var birthday = Date()
    @State private var hasBirthday = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("Assistant on my posts’ comments", isOn: Binding(
                get: { store.enabled },
                set: { store.enabled = $0 }
            ))
            .font(.subheadline.weight(.semibold))

            if store.enabled {
                Text("When a comment on a post you wrote matches a keyword, \(store.selection.displayName) drafts a reply for you to send.")
                    .font(.caption).foregroundStyle(.secondary)

                assistantMascotPicker

                VStack(alignment: .leading, spacing: 8) {
                    Text("Keywords").font(.subheadline.weight(.semibold))
                    ForEach(store.rules) { rule in
                        HStack {
                            Text(rule.keywords.joined(separator: ", "))
                                .font(.subheadline)
                            Spacer()
                            Button(role: .destructive) {
                                store.rules.removeAll { $0.id == rule.id }
                                store.persistRules()
                            } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
                    }
                    HStack {
                        TextField("Add keyword", text: $newKeyword)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addKeyword)
                        Button("Add", action: addKeyword).buttonStyle(.bordered)
                    }
                }

                Toggle(isOn: Binding(get: { store.autoSend }, set: { store.autoSend = $0 })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-send drafts")
                        Text("Off by default. When on, matching replies post without asking — use carefully.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .tint(.orange)

                userContextForm
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.03)))
        .onAppear {
            if let b = store.context.birthday,
               let month = b.month, let day = b.day {
                var c = DateComponents(); c.year = 2000; c.month = month; c.day = day
                if let d = Calendar.current.date(from: c) { birthday = d; hasBirthday = true }
            }
        }
    }

    private var assistantMascotPicker: some View {
        let outfit = MascotWardrobeStore.shared.outfit
        return VStack(alignment: .leading, spacing: 6) {
            Text("Assistant Moliboo").font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ModulaMascotKind.allCases) { kind in
                        let on = store.kindRaw == kind.rawValue
                        Button {
                            guard MascotEntitlements.canUse(kind) else { return }
                            store.kindRaw = kind.rawValue
                        } label: {
                            VStack(spacing: 2) {
                                ModulaMascotFigure(kind: kind, pose: .still(on ? .happy : .idle), size: 26, outfit: on ? outfit : .empty)
                                    .frame(width: 52, height: 46)
                                Text(kind.name).font(.caption2)
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(on ? 0.08 : 0.02)))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .opacity(MascotEntitlements.canUse(kind) ? 1 : 0.4)
                    }
                    ForEach(CustomMascotStore.shared.items) { custom in
                        let on = store.kindRaw == custom.id
                        Button { store.kindRaw = custom.id } label: {
                            VStack(spacing: 2) {
                                CustomMascotFigure(mascot: custom, pose: .still(on ? .happy : .idle), size: 26, outfit: on ? outfit : .empty)
                                    .frame(width: 52, height: 46)
                                Text(custom.name).font(.caption2).lineLimit(1)
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(on ? 0.08 : 0.02)))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var userContextForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("About you (on this device only)", systemImage: "lock.fill")
                .font(.subheadline.weight(.semibold))
            Text("Used only for drafting replies. Never uploaded.")
                .font(.caption2).foregroundStyle(.secondary)
            TextField("Name", text: Binding(get: { store.context.name }, set: { store.context.name = $0; store.persistContext() }))
                .textFieldStyle(.roundedBorder)
            TextField("Pronouns", text: Binding(get: { store.context.pronouns }, set: { store.context.pronouns = $0; store.persistContext() }))
                .textFieldStyle(.roundedBorder)
            TextField("Bio", text: Binding(get: { store.context.bio }, set: { store.context.bio = $0; store.persistContext() }), axis: .vertical)
                .lineLimit(2...3)
                .textFieldStyle(.roundedBorder)
            TextField("Notes for the Moliboo", text: Binding(get: { store.context.notes }, set: { store.context.notes = $0; store.persistContext() }), axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
            Toggle("Birthday", isOn: $hasBirthday)
            if hasBirthday {
                DatePicker("Birthday", selection: $birthday, displayedComponents: .date)
                    .onChange(of: birthday) { _, date in
                        let c = Calendar.current.dateComponents([.month, .day], from: date)
                        store.context.birthday = c
                        store.persistContext()
                    }
            } else if store.context.birthday != nil {
                Color.clear.onAppear {
                    store.context.birthday = nil
                    store.persistContext()
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.04)))
    }

    private func addKeyword() {
        let kw = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !kw.isEmpty else { return }
        store.rules.append(.fresh(keywords: [kw]))
        store.persistRules()
        newKeyword = ""
        HapticEngine.shared.play(.selection)
    }
}

// MARK: - The one Studio entry point

/// Every Studio link (World, Settings hub, composer picker "Dress up", Profile long-press, Settings → Composer)
/// lands here: the Living (3D) Studio when 3D Moliboos are on and the character has a 3D model, otherwise the
/// classic 2D Studio (the rollback path behind `dev.moliboo.native3D`).
struct MolibooStudioEntry: View {
    /// nil = open the Studio with no panel up.
    var tab: MascotStudioView.StudioTab? = .wardrobe
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    var body: some View {
        if MolibooFeatureFlags.native3DEnabled, MolibooRegistry.has3D(kindRaw) {
            MolibooLivingStudioView(characterID: kindRaw, initialPanel: tab.map { $0 == .wardrobe ? .wardrobe : .style }, moreTab: tab ?? .rewards)
        } else {
            MascotStudioView(initialTab: tab ?? .wardrobe)
        }
    }
}

// MARK: - Compact dress-up sheet (from hold-to-swap picker / Profile long-press)

struct MascotDressUpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MolibooStudioEntry(tab: .wardrobe)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

// MARK: - Profile mascot chip

struct ProfileMascotChip: View {
    var size: CGFloat = 36
    var onLongPress: (() -> Void)? = nil

    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    @AppStorage(MascotProfileSettings.showOnProfileKey) private var show = true
    @State private var brain = MascotBrain()
    @State private var dressUp = false
    private var wardrobe = MascotWardrobeStore.shared

    init(size: CGFloat = 36, onLongPress: (() -> Void)? = nil) {
        self.size = size
        self.onLongPress = onLongPress
    }

    var body: some View {
        let selection = MascotSelection.resolve(raw: kindRaw)
        if show, selection != .off {
            ZStack {
                if let bg = wardrobe.outfit.background {
                    MascotSceneView(item: bg, dye: wardrobe.outfit.color(for: .background))
                        .frame(width: size * 1.7, height: size * 1.7)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                }
                MascotDressedLive(selection: selection, size: size, brain: brain, showsShadow: wardrobe.outfit.background == nil, outfit: wardrobe.outfit)
            }
            .frame(width: size * 2.2, height: size * 2.0)
            .contentShape(Rectangle())
            .onTapGesture { brain.hop(burst: .sparkle); MascotSound.shared.play(.hop) }
            .onLongPressGesture(minimumDuration: 0.4) {
                HapticEngine.shared.play(.contextOpen)
                dressUp = true
                onLongPress?()
            }
            .sheet(isPresented: $dressUp) { MascotDressUpSheet() }
            .onReceive(NotificationCenter.default.publisher(for: .mascotOutfitDidChange)) { _ in brain.outfitChanged() }
            .accessibilityLabel("Your Moliboo")
            .accessibilityHint("Long-press to dress up")
            .accessibilityIdentifier("profile.mascot")
            .onAppear {
                MascotProgressStore.shared.touchDay()
                _ = wardrobe.applyOutfitOfTheDayIfNeeded()
                _ = wardrobe.applyBirthdayOutfitIfNeeded(birthday: MascotAssistantStore.shared.context.birthday)
            }
        }
    }
}

/// Avatar replacement: dressed mascot inside a circle ring (scene behind when one is equipped).
struct MascotAvatarView: View {
    var size: CGFloat
    @AppStorage(ModulaMascotSettings.kindKey) private var kindRaw = ModulaMascotKind.pip.rawValue
    @State private var brain = MascotBrain()
    private var wardrobe = MascotWardrobeStore.shared

    init(size: CGFloat) {
        self.size = size
    }

    var body: some View {
        let selection = MascotSelection.resolve(raw: kindRaw)
        let figureSize = size * 0.5
        ZStack {
            if let bg = wardrobe.outfit.background {
                MascotSceneView(item: bg, dye: wardrobe.outfit.color(for: .background))
            } else {
                Circle().fill(selection.accent.opacity(0.35))
            }
            if case .off = selection {
                Image(systemName: "pawprint.fill").font(.system(size: size * 0.35)).foregroundStyle(.secondary)
            } else {
                MascotDressedLive(selection: selection, size: figureSize, brain: brain, showsShadow: false, outfit: wardrobe.outfit)
                    .offset(y: size * 0.04)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// MARK: - Profile settings toggles

struct MascotProfileSettingsSection: View {
    @AppStorage(MascotProfileSettings.showOnProfileKey) private var show = true
    @AppStorage(MascotProfileSettings.useAsAvatarKey) private var asAvatar = false

    var body: some View {
        Section {
            Toggle("Show Moliboo on Profile", isOn: $show)
            Toggle("Use Moliboo as avatar", isOn: $asAvatar)
        } header: {
            Text("Profile Moliboo")
        } footer: {
            Text("Your dressed Moliboo (and its scene) appears on your Profile. Long-press it there to open the wardrobe.")
        }
    }
}
