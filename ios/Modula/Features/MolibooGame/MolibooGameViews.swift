import SwiftUI

// MARK: - Shared pieces

/// Glossy 2D item icon from `MolibooItems.xcassets` (generated batch, see docs/moliboo/ITEM_ART.md).
struct MolibooItemIcon: View {
    let iconKey: String
    var size: CGFloat = 64
    var locked = false
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if UIImage(named: iconKey) != nil {
                    Image(iconKey).resizable().scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).fill(Color.primary.opacity(0.06))
                        .overlay(Image(systemName: "sparkles").foregroundStyle(.secondary))
                }
            }
            .frame(width: size, height: size)
            .saturation(locked ? 0.25 : 1)
            .opacity(locked ? 0.7 : 1)
            if locked {
                Image(systemName: "lock.fill").font(.system(size: size * 0.18, weight: .bold))
                    .padding(size * 0.06).background(.thinMaterial, in: Circle()).offset(x: 2, y: 2)
            }
        }
        .accessibilityHidden(true)
    }
}

struct MolibooRarityDot: View {
    let rarity: String
    var color: Color {
        switch rarity {
        case "uncommon": Color(red: 0.36, green: 0.72, blue: 0.45)
        case "rare": Color(red: 0.30, green: 0.56, blue: 0.95)
        case "epic": Color(red: 0.62, green: 0.40, blue: 0.92)
        case "legendary": Color(red: 0.95, green: 0.68, blue: 0.20)
        default: Color.secondary
        }
    }
    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7).accessibilityLabel(rarity.capitalized)
    }
}

/// Goal-gradient progress bar: real server counts only.
struct MolibooProgressBar: View {
    let fraction: Double
    var tint: Color = .accentColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(8, geo.size.width * fraction))
                    .animation(reduceMotion ? nil : .spring(duration: 0.45), value: fraction)
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityValue("\(Int(fraction * 100)) percent")
    }
}

private struct MolibooGameMessage: ViewModifier {
    @Bindable var store: MolibooGameStore
    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let m = store.message {
                Text(m).font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .modulaGlass(in: Capsule(), interactive: false)
                    .padding(.bottom, 12)
                    .task(id: m) { try? await Task.sleep(for: .seconds(2.2)); if store.message == m { store.message = nil } }
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }
}

private struct MolibooGameUnavailable: View {
    var body: some View {
        ContentUnavailableView("Moliboo games are coming", systemImage: "sparkles",
                               description: Text("Inventory, outfits and quests switch on once the Moliboo game service is live."))
    }
}

// MARK: - Studio "Outfits" panel

/// Studio → Outfits: curated full outfits (hat + hair + clothes + accessories as one set),
/// your own saved outfits, and an entry to the Inventory.
struct MolibooOutfitsPanel: View {
    let characterID: String
    @Environment(AppEnvironment.self) private var app
    @State private var store: MolibooGameStore?
    @State private var segment = 0
    @State private var naming = false
    @State private var newName = ""
    @State private var showInventory = false

    var body: some View {
        Group {
            if !MolibooGameFlags.enabled { MolibooGameUnavailable() }
            else if let store { content(store).modifier(MolibooGameMessage(store: store)) }
            else { ProgressView().frame(maxWidth: .infinity, minHeight: 160) }
        }
        .task {
            guard MolibooGameFlags.enabled, store == nil else { return }
            let s = MolibooGameStore(nativeCharacterID: characterID, client: app.client)
            store = s
            await s.loadAll()
        }
    }

    private func content(_ store: MolibooGameStore) -> some View {
        VStack(spacing: 12) {
            HStack {
                Picker("Outfits", selection: $segment) {
                    Text("Full outfits").tag(0)
                    Text("My outfits").tag(1)
                }
                .pickerStyle(.segmented)
                Button { showInventory = true } label: { Label("Inventory", systemImage: "square.grid.3x3.fill").labelStyle(.iconOnly) }
                    .frame(width: 44, height: 44)
                    .modulaGlass(in: Circle(), interactive: true)
                    .accessibilityLabel("Inventory")
                    .accessibilityIdentifier("moliboo.outfits.inventory")
            }
            .padding(.horizontal, 20)
            ScrollView {
                LazyVStack(spacing: 12) {
                    if segment == 0 {
                        ForEach(store.sets) { set in OutfitSetCard(set: set, worn: store.state?.equipped.sourceSetId == set.setId) { Task { await store.equip(set: set) } } }
                    } else {
                        Button { newName = ""; naming = true } label: {
                            Label("Save what I’m wearing", systemImage: "plus.circle.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("moliboo.outfits.save")
                        if store.saved.isEmpty {
                            Text("Mix pieces in the Wardrobe, then save the look here.").font(.callout).foregroundStyle(.secondary).padding(.top, 12)
                        }
                        ForEach(store.saved) { outfit in savedRow(outfit, store) }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 24)
            }
        }
        .disabled(store.busy)
        .alert("Name this outfit", isPresented: $naming) {
            TextField("Cosy Sunday", text: $newName)
            Button("Save") { let n = newName.trimmingCharacters(in: .whitespaces); if !n.isEmpty { Task { await store.saveCurrent(named: String(n.prefix(40))) } } }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showInventory) {
            NavigationStack { MolibooInventoryView(store: store) }.presentationDetents([.large])
        }
    }

    private func savedRow(_ outfit: MolibooSavedOutfit, _ store: MolibooGameStore) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: -14) {
                ForEach(outfit.itemIds.prefix(4), id: \.self) { id in MolibooItemIcon(iconKey: store.item(id)?.iconKey ?? "", size: 40) }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(outfit.name).font(.headline)
                Text("\(outfit.itemIds.count) pieces").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Wear") { Task { await store.equip(saved: outfit) } }.buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(12)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false)
        .contextMenu { Button("Delete", systemImage: "trash", role: .destructive) { Task { await store.delete(outfit) } } }
    }
}

private struct OutfitSetCard: View {
    let set: MolibooCuratedOutfit
    let worn: Bool
    let wear: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                MolibooItemIcon(iconKey: set.iconKey, size: 72, locked: !(set.completion?.complete ?? false))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        MolibooRarityDot(rarity: set.rarity)
                        Text(set.name).font(.headline)
                        if worn { Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.accentColor).accessibilityLabel("Wearing") }
                    }
                    Text(accessLine).font(.caption).foregroundStyle(.secondary)
                    if let c = set.completion {
                        MolibooProgressBar(fraction: Double(c.owned) / Double(max(1, c.total)))
                        Text("\(c.owned) of \(c.total) pieces").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(set.items, id: \.itemId) { item in
                        VStack(spacing: 2) {
                            MolibooItemIcon(iconKey: item.iconKey, size: 44, locked: !item.usable)
                            Text(item.slot.title).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.name), \(item.usable ? "available" : "locked")")
                    }
                }
            }
            if let bonus = set.setBonus {
                Label(bonus.name, systemImage: "sparkles").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            Button(action: wear) {
                Text(set.completion?.complete == true ? (worn ? "Wearing" : "Wear full outfit") : "Unlock every piece to wear")
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .disabled(worn || set.completion?.complete != true)
            .accessibilityIdentifier("moliboo.outfit.wear.\(set.setId)")
        }
        .padding(14)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false)
    }
    private var accessLine: String {
        switch set.access {
        case "free": "Free full outfit"
        case "earnable": "Earn every piece through quests"
        default: "Premium look: cosmetic only"
        }
    }
}

// MARK: - Inventory

struct MolibooInventoryView: View {
    @Bindable var store: MolibooGameStore
    @State private var slot: MolibooWearableSlot?
    @State private var ownedOnly = false
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 10)]

    private var entries: [MolibooInventoryEntry] {
        (store.inventory?.entries ?? []).filter { (slot == nil || $0.item.slot == slot) && (!ownedOnly || $0.usable) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let c = store.inventory?.counts {
                    HStack(spacing: 10) {
                        stat("\(c.owned)", "Earned")
                        stat("\(c.free)", "Free")
                        stat("\(c.locked)", "To unlock")
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("All", nil)
                        ForEach(MolibooWearableSlot.allCases) { s in chip(s.title, s) }
                    }
                }
                Toggle("Only what I can wear", isOn: $ownedOnly).font(.callout)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(entries) { e in cell(e) }
                }
            }
            .padding(20)
        }
        .navigationTitle("Inventory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .refreshable { await store.loadAll() }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) { Text(value).font(.title3.weight(.bold)); Text(label).font(.caption).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity, minHeight: 60)
            .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: false)
    }

    private func chip(_ title: String, _ s: MolibooWearableSlot?) -> some View {
        let on = slot == s
        return Button(title) { slot = s }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14).frame(minHeight: 36)
            .foregroundStyle(on ? Color.accentColor : .primary)
            .modulaGlass(in: Capsule(), interactive: true, tint: on ? Color.accentColor.opacity(0.18) : nil)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func cell(_ e: MolibooInventoryEntry) -> some View {
        VStack(spacing: 4) {
            MolibooItemIcon(iconKey: e.item.iconKey, size: 72, locked: !e.usable)
            HStack(spacing: 4) { MolibooRarityDot(rarity: e.item.rarity); Text(e.item.name).font(.caption2.weight(.semibold)).lineLimit(1) }
            Text(statusLine(e)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(e.item.name), \(e.item.slot.title), \(statusLine(e))")
    }

    private func statusLine(_ e: MolibooInventoryEntry) -> String {
        switch e.status {
        case "owned": "Earned"
        case "free": "Free"
        case "earnable_locked": "Unlock via a quest"
        default: "Premium"
        }
    }
}

// MARK: - Skills, buffs, care & quests (Moliboo detail / care)

/// Signature skill + active buffs + care buttons + friendship. Drop into a Moliboo detail or care screen.
struct MolibooSkillsBuffsCard: View {
    @Bindable var store: MolibooGameStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let f = store.state?.friendship {
                HStack {
                    Label("Friendship level \(f.level)", systemImage: "heart.fill").font(.headline)
                    Spacer()
                    if f.bonusPct > 0 { Text("+\(f.bonusPct)% XP").font(.caption.weight(.bold)).foregroundStyle(Color.accentColor) }
                }
                MolibooProgressBar(fraction: Double(f.xpIntoLevel) / Double(max(1, f.xpForNext)))
            }
            if let skill = store.state?.skill { skillRow(skill) }
            careRow
            buffs
        }
        .padding(16)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: false)
    }

    private func skillRow(_ skill: MolibooSkill) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2.weight(.bold)).foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(LinearGradient(colors: [Color.accentColor.opacity(0.75), Color.accentColor], startPoint: .top, endPoint: .bottom), in: Circle())
                .scaleEffect(pulse && !reduceMotion ? 1.08 : 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(skill.name).font(.headline)
                Text(skill.description).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if !skill.ready, let at = skill.availableAt.flatMap(MolibooGameDates.parse) {
                    Text("Resting · ready \(at, style: .relative)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button("Use") {
                if !reduceMotion { withAnimation(.spring(duration: 0.35)) { pulse = true } }
                Task { await store.useSkill(); pulse = false }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!skill.ready || store.busy)
            .accessibilityHint("Plays the signature animation and adds a short glow")
            .accessibilityIdentifier("moliboo.skill.use")
        }
    }

    private var careRow: some View {
        HStack(spacing: 8) {
            ForEach(MolibooCareAction.allCases) { a in
                Button { Task { await store.care(a) } } label: {
                    VStack(spacing: 3) { Image(systemName: a.symbol).font(.body.weight(.semibold)); Text(a.title).font(.caption2.weight(.semibold)) }
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.plain)
                .modulaGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
                .accessibilityIdentifier("moliboo.care.\(a.rawValue)")
            }
        }
        .disabled(store.busy)
    }

    @ViewBuilder private var buffs: some View {
        let list = store.state?.buffs ?? []
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Active buffs").font(.subheadline.weight(.semibold))
                ForEach(list) { b in
                    HStack(spacing: 8) {
                        Image(systemName: b.source == "set_bonus" ? "tshirt.fill" : "sparkle").foregroundStyle(Color.accentColor)
                        Text(b.name ?? "Buff").font(.callout.weight(.medium))
                        if b.maxStacks > 1 { Text("×\(b.stacks)").font(.caption.weight(.bold)).foregroundStyle(.secondary) }
                        Spacer()
                        if let d = b.expiresDate { Text(d, style: .timer).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                        else { Text("While worn").font(.caption).foregroundStyle(.secondary) }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Daily / weekly quests, achievements and collection unlocks. No streaks, no penalties.
struct MolibooQuestsPanel: View {
    @Bindable var store: MolibooGameStore
    private let order = ["daily", "weekly", "collection", "achievement"]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(order, id: \.self) { kind in
                let list = store.quests.filter { $0.kind == kind }
                if !list.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title(kind)).font(.headline).accessibilityAddTraits(.isHeader)
                        ForEach(list) { q in row(q) }
                    }
                }
            }
            activities
            Text("No streaks: missing a day never costs you anything. Rewards are always shown up front.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func title(_ kind: String) -> String {
        switch kind {
        case "daily": "Today"
        case "weekly": "This week"
        case "collection": "Collect outfit pieces"
        default: "Achievements"
        }
    }

    private func row(_ q: MolibooQuest) -> some View {
        HStack(spacing: 12) {
            rewardIcon(q)
            VStack(alignment: .leading, spacing: 4) {
                Text(q.title).font(.callout.weight(.semibold))
                Text(q.description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                MolibooProgressBar(fraction: q.fraction)
                Text("\(q.progress)/\(q.target) · \(rewardLine(q))").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if q.claimed { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor).accessibilityLabel("Collected") }
            else if q.completed {
                Button("Collect") { Task { await store.claim(q) } }.buttonStyle(.borderedProminent).controlSize(.small)
                    .accessibilityIdentifier("moliboo.quest.claim.\(q.questId)")
            }
        }
        .padding(12)
        .modulaGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: false)
    }

    @ViewBuilder private func rewardIcon(_ q: MolibooQuest) -> some View {
        if let item = q.reward.item { MolibooItemIcon(iconKey: item.iconKey, size: 44) }
        else if q.reward.type == "surprise_item" { Image(systemName: "gift.fill").font(.title2).frame(width: 44, height: 44).foregroundStyle(Color.accentColor) }
        else { Image(systemName: "heart.fill").font(.title2).frame(width: 44, height: 44).foregroundStyle(.pink) }
    }

    private func rewardLine(_ q: MolibooQuest) -> String {
        switch q.reward.type {
        case "item": q.reward.item?.name ?? "Item"
        case "surprise_item": "Surprise from \(q.reward.poolItems?.count ?? 0) shown items"
        default: "+\(q.reward.amount ?? 0) friendship"
        }
    }

    private var activities: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mini-activities").font(.headline)
            HStack(spacing: 8) {
                ForEach(MolibooActivity.allCases) { a in
                    NavigationLink { MolibooMiniActivityView(activity: a, store: store) } label: {
                        Text(a.title).font(.caption.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: Capsule(), interactive: true)
                }
            }
        }
    }
}

/// Tiny, non-timed tap activity (Bubble Pop / Star Catch / Memory Match share one gentle mechanic for v1):
/// tap 8 glossy bubbles. No score pressure, no timer; Reduce Motion keeps everything static.
struct MolibooMiniActivityView: View {
    let activity: MolibooActivity
    @Bindable var store: MolibooGameStore
    @State private var popped: Set<Int> = []
    @State private var reported = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let count = 8
    var body: some View {
        VStack(spacing: 20) {
            Text(activity.title).font(.title2.weight(.bold))
            Text(popped.count == count ? "All done!" : "Tap each bubble. Take your time.").foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                ForEach(0..<count, id: \.self) { i in
                    Button { pop(i) } label: {
                        Circle()
                            .fill(RadialGradient(colors: [.white, Color.accentColor.opacity(0.55)], center: .topLeading, startRadius: 2, endRadius: 46))
                            .overlay(Circle().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 2))
                            .frame(width: 64, height: 64)
                            .scaleEffect(popped.contains(i) ? (reduceMotion ? 1 : 0.2) : 1)
                            .opacity(popped.contains(i) ? 0.15 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(popped.contains(i))
                    .accessibilityLabel(popped.contains(i) ? "Popped" : "Bubble \(i + 1)")
                }
            }
            .padding()
            Spacer()
        }
        .padding()
        .modifier(MolibooGameMessage(store: store))
    }
    private func pop(_ i: Int) {
        if reduceMotion { popped.insert(i) } else { _ = withAnimation(.spring(duration: 0.3)) { popped.insert(i) } }
        if popped.count == count, !reported { reported = true; Task { await store.finish(activity) } }
    }
}

/// Studio → "Care & quests" panel: skills, buffs, care and quests for the Moliboo on stage.
struct MolibooCareQuestsPanel: View {
    let characterID: String
    @Environment(AppEnvironment.self) private var app
    @State private var store: MolibooGameStore?
    var body: some View {
        Group {
            if !MolibooGameFlags.enabled { MolibooGameUnavailable() }
            else if let store {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 16) {
                            MolibooSkillsBuffsCard(store: store)
                            MolibooQuestsPanel(store: store)
                        }
                        .padding(.horizontal, 20).padding(.bottom, 24)
                    }
                    .toolbar(.hidden, for: .navigationBar)
                }
                .modifier(MolibooGameMessage(store: store))
            } else { ProgressView().frame(maxWidth: .infinity, minHeight: 160) }
        }
        .task {
            guard MolibooGameFlags.enabled, store == nil else { return }
            let s = MolibooGameStore(nativeCharacterID: characterID, client: app.client)
            store = s
            await s.loadAll()
        }
    }
}
