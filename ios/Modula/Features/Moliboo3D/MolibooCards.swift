import SwiftUI
import CoreMotion

// MARK: - MOL-04 Moliboo trading cards (first pass, dev flag `dev.moliboo.cards`)
//
// Free "Founding Collection" only: no purchases, no payments, no backend. Ownership is local (UserDefaults).
// Motion budget: every animated surface is a TimelineView capped at 30 fps, paused off-screen, when the scene is
// inactive, or under Reduce Motion. CoreMotion runs at 30 Hz only while a card is being inspected.

enum MolibooCardFlags {
    static let key = "dev.moliboo.cards"
    #if DEBUG
    static let defaultOn = true
    #else
    static let defaultOn = false
    #endif
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: key) == nil ? defaultOn : UserDefaults.standard.bool(forKey: key)
    }
}

// MARK: Model

enum MolibooCardRarity: String, CaseIterable, Codable, Comparable, Sendable {
    case common, rare, epic, legendary
    var title: String { rawValue.capitalized }
    var rank: Int { Self.allCases.firstIndex(of: self)! }
    static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
    var gems: Int { rank + 1 }
    /// Frame colours (angular gradient around the border).
    var frame: [Color] {
        switch self {
        case .common: [Color(white: 0.86), Color(white: 0.62), Color(white: 0.92), Color(white: 0.86)]
        case .rare: [Color(red: 0.35, green: 0.75, blue: 1), Color(red: 0.2, green: 0.45, blue: 0.95), Color(red: 0.6, green: 0.9, blue: 1), Color(red: 0.35, green: 0.75, blue: 1)]
        case .epic: [Color(red: 0.78, green: 0.45, blue: 1), Color(red: 1, green: 0.45, blue: 0.8), Color(red: 0.5, green: 0.35, blue: 1), Color(red: 0.78, green: 0.45, blue: 1)]
        case .legendary: [Color(red: 1, green: 0.85, blue: 0.35), Color(red: 1, green: 0.6, blue: 0.2), Color(red: 1, green: 0.97, blue: 0.7), Color(red: 1, green: 0.75, blue: 0.25), Color(red: 1, green: 0.85, blue: 0.35)]
        }
    }
    var glow: Color { frame[0] }
    var glowRadius: CGFloat { [1, 2, 3, 5][rank] }
    var holoStrength: Double { [0.04, 0.10, 0.16, 0.22][rank] }
    var sparkleCount: Int { [6, 12, 20, 34][rank] }
    /// Pack roll weights (out of 100).
    var weight: Int { [62, 26, 10, 2][rank] }
}

enum MolibooElement: String, CaseIterable, Codable, Sendable {
    case earth, water, air, fire, light, cosmic
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .earth: "leaf.fill"; case .water: "drop.fill"; case .air: "wind"
        case .fire: "flame.fill"; case .light: "sun.max.fill"; case .cosmic: "moon.stars.fill"
        }
    }
    var colors: [Color] {
        switch self {
        case .earth: [Color(red: 0.42, green: 0.74, blue: 0.40), Color(red: 0.16, green: 0.36, blue: 0.20)]
        case .water: [Color(red: 0.36, green: 0.74, blue: 0.98), Color(red: 0.10, green: 0.28, blue: 0.56)]
        case .air: [Color(red: 0.78, green: 0.90, blue: 1.0), Color(red: 0.36, green: 0.52, blue: 0.74)]
        case .fire: [Color(red: 1.0, green: 0.56, blue: 0.30), Color(red: 0.56, green: 0.14, blue: 0.12)]
        case .light: [Color(red: 1.0, green: 0.90, blue: 0.50), Color(red: 0.70, green: 0.48, blue: 0.16)]
        case .cosmic: [Color(red: 0.56, green: 0.42, blue: 0.96), Color(red: 0.10, green: 0.08, blue: 0.30)]
        }
    }
}

struct MolibooCardMove: Codable, Equatable, Sendable, Hashable {
    let name: String
    let power: Int
}

struct MolibooCard: Codable, Equatable, Identifiable, Sendable, Hashable {
    let id: String          // card id, e.g. "founding.pebble"
    let characterID: String // registered character id
    let name: String
    let rarity: MolibooCardRarity
    let level: Int
    let element: MolibooElement
    let moves: [MolibooCardMove]
    let tagline: String
    let hearts: Int
    var kind: ModulaMascotKind? { ModulaMascotKind(rawValue: characterID) }
}

// MARK: Catalogue (data-driven: JSON, registered characters only)

enum MolibooCardCatalogue {
    static let registeredCharacterIDs = ["pebble", "pip", "moss", "tofu", "bolt", "nimbus", "mochi", "sprout", "ember", "tuck"]
    static let collectionName = "Founding Collection"
    static let packSize = 5

    static let json = """
    [
     {"id":"founding.pebble","characterID":"pebble","name":"Pebble","rarity":"legendary","level":30,"element":"earth","hearts":5,
      "tagline":"Steady as stone, soft as moss.","moves":[{"name":"Pebble Toss","power":40},{"name":"Cap Tip","power":65},{"name":"Bedrock Hug","power":120}]},
     {"id":"founding.ember","characterID":"ember","name":"Ember","rarity":"epic","level":24,"element":"fire","hearts":4,
      "tagline":"A tiny spark with a big warm heart.","moves":[{"name":"Cinder Puff","power":35},{"name":"Cosy Glow","power":60},{"name":"Bonfire Twirl","power":95}]},
     {"id":"founding.bolt","characterID":"bolt","name":"Bolt","rarity":"epic","level":22,"element":"light","hearts":4,
      "tagline":"Zips first, thinks later.","moves":[{"name":"Static Hop","power":30},{"name":"Flash Dash","power":55},{"name":"Thunder Zoom","power":90}]},
     {"id":"founding.nimbus","characterID":"nimbus","name":"Nimbus","rarity":"rare","level":16,"element":"air","hearts":3,
      "tagline":"Floats wherever the breeze is kind.","moves":[{"name":"Drizzle","power":25},{"name":"Cloud Nap","power":40},{"name":"Gust Glide","power":70}]},
     {"id":"founding.tuck","characterID":"tuck","name":"Tuck","rarity":"rare","level":15,"element":"cosmic","hearts":3,
      "tagline":"Dreams in constellations.","moves":[{"name":"Star Blink","power":25},{"name":"Lullaby","power":45},{"name":"Moonbeam","power":75}]},
     {"id":"founding.tofu","characterID":"tofu","name":"Tofu","rarity":"rare","level":14,"element":"water","hearts":3,
      "tagline":"Wobbly, wise and always calm.","moves":[{"name":"Jiggle","power":20},{"name":"Splash","power":45},{"name":"Soy Wave","power":70}]},
     {"id":"founding.pip","characterID":"pip","name":"Pip","rarity":"common","level":8,"element":"light","hearts":2,
      "tagline":"Small chirp, bright day.","moves":[{"name":"Peep","power":15},{"name":"Sunny Hop","power":30},{"name":"Chirp Chorus","power":50}]},
     {"id":"founding.moss","characterID":"moss","name":"Moss","rarity":"common","level":9,"element":"earth","hearts":2,
      "tagline":"Grows on you. Literally.","moves":[{"name":"Spore Puff","power":15},{"name":"Root Hold","power":30},{"name":"Green Blanket","power":55}]},
     {"id":"founding.mochi","characterID":"mochi","name":"Mochi","rarity":"common","level":7,"element":"water","hearts":2,
      "tagline":"Squish first, ask later.","moves":[{"name":"Squish","power":15},{"name":"Bounce","power":25},{"name":"Sweet Splash","power":50}]},
     {"id":"founding.sprout","characterID":"sprout","name":"Sprout","rarity":"common","level":6,"element":"earth","hearts":2,
      "tagline":"Every day, a little taller.","moves":[{"name":"Leaf Wave","power":10},{"name":"Sun Soak","power":25},{"name":"Bloom Burst","power":45}]}
    ]
    """

    static let cards: [MolibooCard] = {
        (try? JSONDecoder().decode([MolibooCard].self, from: Data(json.utf8))) ?? []
    }()

    static func card(id: String) -> MolibooCard? { cards.first { $0.id == id } }
    static func cards(of r: MolibooCardRarity) -> [MolibooCard] { cards.filter { $0.rarity == r } }
}

/// Small deterministic RNG so pack rolls are testable.
struct MolibooSplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum MolibooPackRoller {
    /// The very first Founding pack is a welcome: 4 commons/rares and Pebble (Legendary) revealed last.
    static func welcomePack() -> [MolibooCard] {
        ["founding.pip", "founding.moss", "founding.nimbus", "founding.ember", "founding.pebble"].compactMap(MolibooCardCatalogue.card(id:))
    }

    /// Later packs: weighted rarity per slot, last slot guaranteed Rare or better, sorted so the best card is revealed last.
    static func roll(seed: UInt64) -> [MolibooCard] {
        var rng = MolibooSplitMix(state: seed)
        var out: [MolibooCard] = []
        for slot in 0..<MolibooCardCatalogue.packSize {
            var rarity = rollRarity(&rng)
            if slot == MolibooCardCatalogue.packSize - 1, rarity == .common { rarity = .rare }
            // No duplicates within one pack: prefer cards not already pulled in this pack.
            let full = MolibooCardCatalogue.cards(of: rarity)
            let fresh = full.filter { c in !out.contains { $0.id == c.id } }
            let pool = fresh.isEmpty ? full : fresh
            out.append(pool[Int(rng.next() % UInt64(pool.count))])
        }
        return out.sorted { $0.rarity < $1.rarity }
    }

    static func rollRarity(_ rng: inout MolibooSplitMix) -> MolibooCardRarity {
        var r = Int(rng.next() % 100)
        for rarity in MolibooCardRarity.allCases { if r < rarity.weight { return rarity }; r -= rarity.weight }
        return .common
    }
}

/// Local ownership. Free packs only.
@MainActor @Observable
final class MolibooCardStore {
    static let shared = MolibooCardStore()
    static let ownedKey = "moliboo.cards.owned.v1"
    static let packsKey = "moliboo.cards.packsOpened.v1"

    private let defaults: UserDefaults
    private(set) var owned: [String: Int]
    private(set) var packsOpened: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest-cards-reset") {
            defaults.removeObject(forKey: Self.ownedKey); defaults.removeObject(forKey: Self.packsKey)
        }
        #endif
        owned = (defaults.dictionary(forKey: Self.ownedKey) as? [String: Int]) ?? [:]
        packsOpened = defaults.integer(forKey: Self.packsKey)
    }

    func count(_ id: String) -> Int { owned[id] ?? 0 }
    var uniqueOwned: Int { MolibooCardCatalogue.cards.filter { count($0.id) > 0 }.count }
    var total: Int { MolibooCardCatalogue.cards.count }

    /// Opens a free Founding pack and adds it to the binder. Returns the cards in reveal order.
    @discardableResult
    func openFoundingPack(seed: UInt64? = nil) -> [MolibooCard] {
        let pack = packsOpened == 0 ? MolibooPackRoller.welcomePack()
                                    : MolibooPackRoller.roll(seed: seed ?? UInt64.random(in: 1...UInt64.max))
        for c in pack { owned[c.id, default: 0] += 1 }
        packsOpened += 1
        defaults.set(owned, forKey: Self.ownedKey)
        defaults.set(packsOpened, forKey: Self.packsKey)
        return pack
    }
}

// MARK: Tilt (CoreMotion, drag fallback)

@MainActor @Observable
final class MolibooTiltSource {
    /// -1...1 on each axis.
    var tilt: CGSize = .zero
    private(set) var usingMotion = false
    private let manager = CMMotionManager()
    private var base: (Double, Double)?

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        usingMotion = true
        base = nil
        manager.deviceMotionUpdateInterval = 1.0 / 30   // capped
        manager.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let m else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                let r = m.attitude.roll, p = m.attitude.pitch
                if self.base == nil { self.base = (r, p) }
                let b = self.base!
                let x = max(-1, min(1, (r - b.0) / 0.5)), y = max(-1, min(1, (p - b.1) / 0.5))
                if abs(x - self.tilt.width) > 0.01 || abs(y - self.tilt.height) > 0.01 { self.tilt = CGSize(width: x, height: y) }
            }
        }
    }

    func stop() {
        if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
        usingMotion = false
    }
}

// MARK: Card view

struct MolibooTradingCardView: View {
    let card: MolibooCard
    var width: CGFloat = 240
    var tilt: CGSize = .zero
    var animating = false
    var faceDown = false

    private static let base = CGSize(width: 240, height: 336)
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 22, style: .continuous) }

    var body: some View {
        ZStack {
            if faceDown { back } else if animating {
                // Live inspect/pack only — binder slots stay flat (no continuous foil/shimmer).
                front.modifier(MolibooLegendaryShimmer(on: card.rarity == .legendary, strength: 0.25, animated: true))
            } else {
                front
            }
        }
        .frame(width: Self.base.width, height: Self.base.height)
        .scaleEffect(width / Self.base.width)
        .frame(width: width, height: width * Self.base.height / Self.base.width)
        .rotation3DEffect(.degrees(Double(tilt.width) * 12), axis: (0, 1, 0), perspective: 0.6)
        .rotation3DEffect(.degrees(Double(-tilt.height) * 10), axis: (1, 0, 0), perspective: 0.6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(faceDown ? "Face-down card" : "\(card.name), \(card.rarity.title), level \(card.level), \(card.element.title)")
    }

    @Environment(\.colorScheme) private var scheme

    /// Clean, Wallet-like face: full-bleed art window, then calm system typography on the card surface.
    /// Rarity reads from a small pill (and a thin rim for Epic / Legendary) rather than neon frames.
    private var front: some View {
        ZStack {
            shape.fill(Color(uiColor: scheme == .dark ? .secondarySystemBackground : .systemBackground))
            VStack(alignment: .leading, spacing: 0) {
                art
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(card.name)
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        rarityPill
                    }
                    HStack(spacing: 6) {
                        Image(systemName: card.element.icon).font(.system(size: 10, weight: .semibold))
                        Text("\(card.element.title) · Lv \(card.level)")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(Array(card.moves.enumerated()), id: \.offset) { i, m in
                            if i > 0 { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.5) }
                            HStack {
                                Text(m.name).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                                Spacer()
                                Text("\(m.power)").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .frame(height: 22)
                        }
                    }
                    HStack(spacing: 3) {
                        ForEach(0..<5, id: \.self) { i in
                            Image(systemName: "heart.fill").font(.system(size: 8))
                                .foregroundStyle(i < card.hearts ? Color.pink.opacity(0.85) : Color.primary.opacity(0.12))
                        }
                        Spacer()
                        Text(card.tagline)
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            if animating { holo }
            shape.strokeBorder(Color.primary.opacity(scheme == .dark ? 0.14 : 0.08), lineWidth: 0.8)
            if card.rarity >= .epic {
                shape.strokeBorder(LinearGradient(colors: card.rarity.frame, startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.75), lineWidth: 1.5)
            }
        }
        .clipShape(shape)
        .shadow(color: .black.opacity(animating ? 0.22 : 0.08), radius: animating ? 18 : 6, y: animating ? 10 : 3)
    }

    private var rarityPill: some View {
        HStack(spacing: 3) {
            Circle().fill(card.rarity.glow).frame(width: 6, height: 6)
            Text(card.rarity.title).font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .fixedSize()
    }

    /// Full-bleed art window with a soft element tint; the character keeps the same scale on every card.
    private var art: some View {
        ZStack {
            LinearGradient(colors: [card.element.colors[0].opacity(scheme == .dark ? 0.45 : 0.40),
                                    card.element.colors[0].opacity(scheme == .dark ? 0.18 : 0.12)],
                           startPoint: .top, endPoint: .bottom)
            if animating, card.rarity >= .rare {
                MolibooSparkleField(count: card.rarity.sparkleCount / 2, color: .white.opacity(0.8), animating: true)
            }
            if let kind = card.kind {
                MolibooHubArt(kind: kind, size: 142)
                    .offset(x: tilt.width * -5, y: 6 + tilt.height * -3)
            }
        }
        .frame(height: 170)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    /// Holographic sheen — only while inspecting (tilt), kept subtle.
    private var holo: some View {
        let shift = (tilt.width + tilt.height) * 0.5
        return ZStack {
            LinearGradient(colors: [.clear, .pink, .yellow, .green, .cyan, .purple, .clear],
                           startPoint: UnitPoint(x: -0.6 + shift, y: -0.2), endPoint: UnitPoint(x: 1.0 + shift, y: 1.2))
                .blendMode(.overlay).opacity(card.rarity.holoStrength * 0.6)
            RadialGradient(colors: [.white.opacity(0.35), .clear], center: UnitPoint(x: 0.5 + tilt.width * 0.45, y: 0.3 + tilt.height * 0.45), startRadius: 0, endRadius: 170)
                .blendMode(.softLight)
        }
        .allowsHitTesting(false)
    }

    /// Quiet back: one deep colour, the bubbly logo and the set name.
    private var back: some View {
        ZStack {
            shape.fill(LinearGradient(colors: [Color(red: 0.16, green: 0.17, blue: 0.24), Color(red: 0.09, green: 0.10, blue: 0.15)], startPoint: .top, endPoint: .bottom))
            VStack(spacing: 12) {
                MoliboosWordmark(height: 24, onDark: true)
                Text(MolibooCardCatalogue.collectionName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
        }
        .clipShape(shape)
    }
}

/// Twinkling sparkles. Static frame when not animating; ≤30 fps when animating.
struct MolibooSparkleField: View {
    var count: Int
    var color: Color
    var animating: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animating)) { ctx in
            let t = animating ? ctx.date.timeIntervalSinceReferenceDate : 1.3
            Canvas { g, size in
                for i in 0..<count {
                    let s = Double(i) * 1.618
                    let x = (s * 97).truncatingRemainder(dividingBy: 1) * size.width
                    let y = ((s * 0.37 + t * 0.02 * (1 + Double(i % 3))).truncatingRemainder(dividingBy: 1)) * size.height
                    let tw = 0.5 + 0.5 * sin(t * 2.4 + s * 3)
                    let r = 1.5 + 2.5 * tw
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: y - r * 2)); p.addLine(to: CGPoint(x: x + r * 0.5, y: y - r * 0.5))
                    p.addLine(to: CGPoint(x: x + r * 2, y: y)); p.addLine(to: CGPoint(x: x + r * 0.5, y: y + r * 0.5))
                    p.addLine(to: CGPoint(x: x, y: y + r * 2)); p.addLine(to: CGPoint(x: x - r * 0.5, y: y + r * 0.5))
                    p.addLine(to: CGPoint(x: x - r * 2, y: y)); p.addLine(to: CGPoint(x: x - r * 0.5, y: y - r * 0.5))
                    p.closeSubpath()
                    g.fill(p, with: .color(color.opacity(0.35 + 0.6 * tw)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: Binder

struct MolibooCardBinderView: View {
    @State private var store = MolibooCardStore.shared
    @State private var pack: [MolibooCard]?
    @State private var inspecting: MolibooCard?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var cardNS
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(MolibooCardCatalogue.cards) { c in slot(c) }
                }
                Text("Founding packs are free. Cards stay on this device.")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.bottom, 32)
            }
            .padding(.horizontal, 20)
        }
        .contentMargins(.bottom, 40, for: .scrollContent)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Cards")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityIdentifier("cards.binder")
        .fullScreenCover(item: Binding(get: { pack.map(MolibooPackBox.init) }, set: { pack = $0?.cards })) { box in
            MolibooPackOpeningView(cards: box.cards) { pack = nil }
        }
        .fullScreenCover(item: $inspecting) { c in
            MolibooCardInspectView(card: c, owned: store.count(c.id))
                .navigationTransition(.zoom(sourceID: c.id, in: cardNS))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(MolibooCardCatalogue.collectionName)
                .font(.title2.weight(.bold))
            ProgressView(value: Double(store.uniqueOwned), total: Double(store.total))
                .tint(Color(red: 0.21, green: 0.61, blue: 0.67))
            Text("\(store.uniqueOwned) of \(store.total) collected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("cards.progress")
            Button { pack = store.openFoundingPack() } label: {
                Label("Open free pack", systemImage: "gift.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.plain)
            .modulaGlass(in: Capsule(), interactive: true, tint: Color(red: 0.21, green: 0.61, blue: 0.67).opacity(0.35), prominent: true)
            .accessibilityIdentifier("cards.openPack")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.top, 8)
    }

    /// Every slot has the same card aspect, sized by the grid column (no fixed widths, no clipping).
    @ViewBuilder private func slot(_ c: MolibooCard) -> some View {
        let n = store.count(c.id)
        if n > 0 {
            Button { inspecting = c } label: {
                Color.clear
                    .aspectRatio(240.0 / 336.0, contentMode: .fit)
                    .overlay { GeometryReader { g in MolibooTradingCardView(card: c, width: g.size.width) } }
                    .overlay(alignment: .topTrailing) {
                        if n > 1 {
                            Text("×\(n)").font(.caption2.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(.regularMaterial, in: Capsule())
                                .padding(8)
                        }
                    }
            }
            .buttonStyle(MolibooSpringPress(enabled: !reduceMotion))
            .matchedTransitionSource(id: c.id, in: cardNS) { $0.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)) }
            .accessibilityIdentifier("cards.slot.\(c.characterID)")
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .aspectRatio(240.0 / 336.0, contentMode: .fit)
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "lock.fill").font(.title3).foregroundStyle(.tertiary)
                        Text(c.rarity.title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement().accessibilityLabel("Not collected yet")
                .accessibilityIdentifier("cards.locked.\(c.characterID)")
        }
    }
}

struct MolibooPackBox: Identifiable { let cards: [MolibooCard]; var id: String { cards.map(\.id).joined() } }

/// Full-screen card viewer (zoom transition from the binder). Tilt with CoreMotion (drag fallback);
/// the sheen only runs while the scene is active and Reduce Motion is off.
struct MolibooCardInspectView: View {
    let card: MolibooCard
    var owned = 1
    @State private var tiltSource = MolibooTiltSource()
    @State private var drag: CGSize = .zero
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private var live: Bool { !reduceMotion && scenePhase == .active }
    private var tilt: CGSize { drag == .zero ? tiltSource.tilt : drag }

    var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width - 56, 340)
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                LinearGradient(colors: [card.element.colors[0].opacity(0.18), .clear], startPoint: .top, endPoint: .center)
                    .ignoresSafeArea()
                VStack(spacing: 22) {
                    Spacer(minLength: 0)
                    MolibooTradingCardView(card: card, width: w, tilt: reduceMotion ? .zero : tilt, animating: live)
                        .gesture(DragGesture(minimumDistance: 8)
                            .onChanged { v in drag = CGSize(width: max(-1, min(1, v.translation.width / 150)), height: max(-1, min(1, v.translation.height / 150))) }
                            .onEnded { _ in withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.7)) { drag = .zero } })
                        .accessibilityIdentifier("cards.inspect.card")
                    VStack(spacing: 4) {
                        Text("\(card.rarity.title) · \(card.element.title)")
                            .font(.subheadline.weight(.semibold))
                        Text(owned > 1 ? "You have \(owned)" : (reduceMotion ? "From the \(MolibooCardCatalogue.collectionName)" : (tiltSource.usingMotion ? "Tilt your phone to catch the shine" : "Drag the card to catch the shine")))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .topTrailing) {
            ModulaGlassIconButton(title: "Close", systemImage: "xmark", size: 44) { dismiss() }
                .padding(.trailing, 20)
                .padding(.top, 8)
                .accessibilityIdentifier("cards.inspect.close")
        }
        .onAppear { if live { tiltSource.start() } }
        .onDisappear { tiltSource.stop() }
        .onChange(of: live) { _, on in on ? tiltSource.start() : tiltSource.stop() }
    }
}

// MARK: Pack opening

struct MolibooPackOpeningView: View {
    let cards: [MolibooCard]
    var onDone: () -> Void

    enum Phase: Equatable { case sealed, tearing, fanned, legendary, done }
    @State private var phase: Phase = .sealed
    @State private var revealed = 0
    @State private var wobble = false
    @State private var fanOut = false
    @State private var legendaryCard: MolibooCard?
    @State private var burst = false
    @State private var flash = false
    @State private var ambient = MolibooTiltSource()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private var motionOn: Bool { !reduceMotion && scenePhase == .active }

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            LinearGradient(colors: [Color.primary.opacity(0.04), Color.clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            if phase == .sealed || phase == .tearing { packView.modifier(MolibooDissolve(progress: phase == .tearing ? 1 : 0)) }
            if phase == .fanned || phase == .legendary || phase == .done { fan }
            if phase == .legendary, let c = legendaryCard { MolibooLegendaryReveal(card: c, animating: motionOn) { continueAfterLegendary() } }
            Circle().fill(.white).frame(width: 40).scaleEffect(flash ? 30 : 0.01).opacity(flash ? 0 : 0.9).allowsHitTesting(false)
            VStack {
                HStack {
                    Spacer()
                    ModulaGlassIconButton(title: "Close", systemImage: "xmark", size: 44) { onDone() }
                        .accessibilityIdentifier("pack.close")
                }
                Spacer()
                if phase == .done {
                    Button { onDone() } label: {
                        Label("Add to binder", systemImage: "books.vertical.fill").font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.plain)
                    .modulaGlass(in: Capsule(), tint: Color(red: 0.21, green: 0.61, blue: 0.67), prominent: true)
                    .accessibilityIdentifier("pack.done")
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(20)
        }
    }

    private var packView: some View {
        VStack(spacing: 22) {
            ZStack {
                // body
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.21, green: 0.61, blue: 0.67), Color(red: 0.36, green: 0.24, blue: 0.70), Color(red: 0.95, green: 0.55, blue: 0.70)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(MolibooSparkleField(count: 8, color: .white, animating: motionOn).clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous)))
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1.5))
                    .offset(y: phase == .tearing ? 40 : 0)
                    .opacity(phase == .tearing ? 0 : 1)
                VStack(spacing: 10) {
                    MoliboosWordmark(height: 30, onDark: true)
                    Text(MolibooCardCatalogue.collectionName.uppercased()).font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(2).foregroundStyle(.white)
                    Text("\(cards.count) cards · Free").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                }
                .opacity(phase == .tearing ? 0 : 1)
                // tear strip
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.9))
                    .frame(width: 240, height: 22)
                    .overlay(Text("TEAR").font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(3).foregroundStyle(.purple))
                    .offset(x: phase == .tearing ? 160 : 0, y: phase == .tearing ? -260 : -170)
                    .rotationEffect(.degrees(phase == .tearing ? 35 : 0))
                    .opacity(phase == .tearing ? 0 : 1)
                // glow seam
                Capsule().fill(RadialGradient(colors: [.white, Color(red: 1, green: 0.9, blue: 0.5), .clear], center: .center, startRadius: 0, endRadius: 140))
                    .frame(width: 280, height: phase == .tearing ? 90 : 4).blur(radius: 6).offset(y: -150)
                    .opacity(phase == .tearing ? 1 : 0.5)
            }
            .frame(width: 250, height: 370)
            .rotationEffect(.degrees(wobble && motionOn ? 2.5 : -2.5))
            .scaleEffect(wobble && motionOn ? 1.02 : 0.98)
            .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
            .onAppear { if motionOn { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { wobble = true } } }
            Button { tear() } label: {
                Label("Tear open", systemImage: "hand.draw.fill").font(.headline).foregroundStyle(.white).padding(.horizontal, 28).frame(minHeight: 50)
            }
            .buttonStyle(.plain)
            .modulaGlass(in: Capsule(), tint: .purple, prominent: true)
            .opacity(phase == .sealed ? 1 : 0)
            .accessibilityIdentifier("pack.tear")
        }
        .onTapGesture { tear() }
    }

    private var fan: some View {
        let n = cards.count
        return ZStack {
            ForEach(Array(cards.enumerated()), id: \.offset) { i, c in
                let mid = Double(n - 1) / 2
                let a = (Double(i) - mid) * 9
                let shown = i < revealed
                // Cards rise out of the opened pack as a stack, then fan out one by one.
                MolibooFlipCard(card: c, faceUp: shown, animating: false, reduceMotion: reduceMotion)
                    .offset(x: fanOut ? CGFloat(Double(i) - mid) * 62 : 0,
                            y: fanOut ? CGFloat(abs(Double(i) - mid)) * 14 : 60)
                    .rotationEffect(.degrees(fanOut ? a : 0), anchor: .bottom)
                    .scaleEffect(fanOut ? 1 : 0.85)
                    .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.78).delay(Double(i) * 0.07), value: fanOut)
                    .zIndex(Double(i))
                    .accessibilityIdentifier("pack.card.\(i)")
            }
        }
        .offset(y: -30)
        .onAppear { fanOut = true }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func tear() {
        guard phase == .sealed else { return }
        HapticEngine.shared.play(.selection)
        Task { @MainActor in
            if motionOn {
                withAnimation(.easeOut(duration: 0.55)) { phase = .tearing }
                withAnimation(.easeOut(duration: 0.7)) { flash = true }
                try? await Task.sleep(for: .milliseconds(600))
                withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) { phase = .fanned }
                try? await Task.sleep(for: .milliseconds(600))
            } else {
                phase = .fanned
            }
            await revealNext()
        }
    }

    private func revealNext() async {
        while revealed < cards.count {
            let c = cards[revealed]
            withAnimation(motionOn ? .spring(response: 0.5, dampingFraction: 0.7) : nil) { revealed += 1 }
            if c.rarity == .legendary {
                try? await Task.sleep(for: .milliseconds(motionOn ? 450 : 50))
                legendaryCard = c
                withAnimation(motionOn ? .easeOut(duration: 0.4) : nil) { phase = .legendary }
                return
            }
            try? await Task.sleep(for: .milliseconds(motionOn ? 420 : 80))
        }
        withAnimation(.snappy) { phase = .done }
    }

    private func continueAfterLegendary() {
        withAnimation(.easeOut(duration: 0.3)) { phase = .fanned }
        Task { @MainActor in await revealNext() }
    }
}

/// A card that flips from back to front around the Y axis.
struct MolibooFlipCard: View {
    let card: MolibooCard
    var faceUp: Bool
    var animating: Bool
    var reduceMotion: Bool

    var body: some View {
        ZStack {
            MolibooTradingCardView(card: card, width: 150, animating: animating, faceDown: true)
                .opacity(faceUp ? 0 : 1)
            MolibooTradingCardView(card: card, width: 150, animating: animating)
                .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (0, 1, 0))
                .opacity(faceUp ? 1 : 0)
        }
        // rotation3DEffect renders into a layer the size of the view, which cut the rarity glow
        // into hard vertical edges. Give the glow room inside the layer, then take it back out.
        .padding(40)
        .rotation3DEffect(.degrees(faceUp && !reduceMotion ? 180 : 0), axis: (0, 1, 0), perspective: 0.5)
        .padding(-40)
    }
}

/// Legendary showcase: golden light rays, an orbit ring, a crown burst and the card front and centre.
struct MolibooLegendaryReveal: View {
    let card: MolibooCard
    var animating: Bool
    var onContinue: () -> Void
    @State private var crown = false
    @State private var tilt = CGSize.zero

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animating)) { ctx in
                let t = animating ? ctx.date.timeIntervalSinceReferenceDate : 0
                ZStack {
                    // light rays
                    ForEach(0..<14, id: \.self) { i in
                        Capsule()
                            .fill(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.45).opacity(0.75), .clear], startPoint: .bottom, endPoint: .top))
                            .frame(width: 22, height: 420)
                            .offset(y: -210)
                            .rotationEffect(.degrees(Double(i) * (360.0 / 14) + t * 12))
                    }
                    .blur(radius: 3)
                    RadialGradient(colors: [Color(red: 1, green: 0.85, blue: 0.4).opacity(0.8), .clear], center: .center, startRadius: 10, endRadius: 260)
                    // orbit ring
                    ZStack {
                        Circle().stroke(LinearGradient(colors: [Color(red: 1, green: 0.95, blue: 0.7), Color(red: 1, green: 0.7, blue: 0.2)], startPoint: .leading, endPoint: .trailing), lineWidth: 3)
                        ForEach(0..<6, id: \.self) { i in
                            let a = Double(i) / 6 * 2 * .pi + t * 0.9
                            Image(systemName: "sparkle").font(.system(size: 16, weight: .bold)).foregroundStyle(.yellow)
                                .offset(x: CGFloat(cos(a)) * 170, y: CGFloat(sin(a)) * 170)
                        }
                    }
                    .frame(width: 340, height: 340)
                    .rotation3DEffect(.degrees(68), axis: (1, 0, 0))
                    MolibooTradingCardView(card: card, width: 230, tilt: CGSize(width: sin(t * 0.8) * 0.5, height: cos(t * 0.6) * 0.3), animating: animating)
                        .scaleEffect(crown ? 1 : 0.6)
                }
            }
            // crown burst
            VStack {
                ZStack {
                    ForEach(0..<10, id: \.self) { i in
                        Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(.yellow)
                            .offset(y: crown ? -62 : 0).rotationEffect(.degrees(Double(i) * 36)).opacity(crown ? 0 : 1)
                    }
                    Image(systemName: "crown.fill").font(.system(size: 46)).foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
                        .shadow(color: .yellow, radius: 16).scaleEffect(crown ? 1 : 0.2)
                }
                .padding(.top, 70)
                Text("LEGENDARY").font(.system(size: 30, weight: .black, design: .rounded)).tracking(4)
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.95, blue: 0.7), Color(red: 1, green: 0.7, blue: 0.2)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .orange, radius: 10)
                Spacer()
                Button(action: onContinue) {
                    Text("Continue").font(.headline).foregroundStyle(.white).padding(.horizontal, 36).frame(minHeight: 50)
                }
                .buttonStyle(.plain)
                .modulaGlass(in: Capsule(), tint: .orange, prominent: true)
                .accessibilityIdentifier("pack.legendary.continue")
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            HapticEngine.shared.play(.selection)
            withAnimation(animating ? .spring(response: 0.7, dampingFraction: 0.55) : nil) { crown = true }
        }
    }
}

private struct MolibooLegendaryShimmer: ViewModifier {
    let on: Bool
    var strength: Double = 0.7
    let animated: Bool
    func body(content: Content) -> some View {
        if on { content.molibooShimmer(strength, animated: animated) } else { content }
    }
}
