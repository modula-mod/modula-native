import SwiftUI

// MARK: - Slots

enum MascotWardrobeSlot: String, CaseIterable, Identifiable, Codable, Sendable {
    case hat, hair, face, top, outerwear, bottom, shoes, accessory, held, back, aura, pet, background, seasonal
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hat: "Hats"
        case .hair: "Hair"
        case .face: "Face"
        case .top: "Tops"
        case .outerwear: "Outerwear"
        case .bottom: "Bottoms"
        case .shoes: "Shoes"
        case .accessory: "Accessories"
        case .held: "Held"
        case .back: "Back"
        case .aura: "Auras"
        case .pet: "Pets"
        case .background: "Scenes"
        case .seasonal: "Seasonal"
        }
    }
    var symbol: String {
        switch self {
        case .hat: "crown.fill"
        case .hair: "comb.fill"
        case .face: "eyeglasses"
        case .top: "tshirt.fill"
        case .outerwear: "jacket.fill"
        case .bottom: "figure.dress.line.vertical.figure"
        case .shoes: "shoe.fill"
        case .accessory: "sparkle"
        case .held: "balloon.fill"
        case .back: "bird.fill"
        case .aura: "sparkles"
        case .pet: "pawprint.fill"
        case .background: "photo.fill"
        case .seasonal: "leaf.fill"
        }
    }
    var defaultNeed: MascotNeed {
        switch self {
        case .hat, .seasonal: .head
        case .hair: .hair
        case .face: .face
        case .top, .outerwear: .torso
        case .bottom: .legsOrFrill
        case .shoes: .feet
        case .accessory: .neck
        case .held: .hand
        case .back: .back
        case .aura: .aura
        case .pet: .ground
        case .background: .scene
        }
    }
}

// MARK: - Rarity

enum MascotWardrobeRarity: Int, CaseIterable, Comparable, Codable, Sendable {
    case common, uncommon, rare, epic, legendary
    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    var title: String {
        switch self {
        case .common: "Common"
        case .uncommon: "Uncommon"
        case .rare: "Rare"
        case .epic: "Epic"
        case .legendary: "Legendary"
        }
    }
    var color: Color {
        switch self {
        case .common: Color(red: 0.62, green: 0.65, blue: 0.70)
        case .uncommon: Color(red: 0.30, green: 0.80, blue: 0.45)
        case .rare: Color(red: 0.30, green: 0.58, blue: 1.0)
        case .epic: Color(red: 0.70, green: 0.38, blue: 1.0)
        case .legendary: Color(red: 1.0, green: 0.68, blue: 0.18)
        }
    }
    var glows: Bool { self >= .rare }
}

enum MascotPattern: String, Sendable, Hashable {
    case plain, stripes, dots, plaid, knit, stars, hearts, check, floral, zigzag
}

enum MascotUnlock: Sendable, Hashable {
    case free
    case premium
    case coins(Int)
    case achievement(String)
}

// MARK: - Item

struct MascotWardrobeItem: Identifiable, Hashable, Sendable {
    let id: String
    let slot: MascotWardrobeSlot
    let name: String
    let blurb: String
    let rarity: MascotWardrobeRarity
    let style: String
    let pattern: MascotPattern
    let dyes: [Color]
    let unlock: MascotUnlock
    let need: MascotNeed
    let seasonalMonths: [Int]

    var isPremium: Bool { if case .premium = unlock { return true }; return false }
    var coinPrice: Int? { if case .coins(let p) = unlock { return p }; return nil }
    var achievementID: String? { if case .achievement(let a) = unlock { return a }; return nil }
    var isSeasonal: Bool { !seasonalMonths.isEmpty }
    var tint: Color { dyes.first ?? .gray }
    func dye(_ index: Int) -> Color { dyes.isEmpty ? .gray : dyes[min(max(0, index), dyes.count - 1)] }

    func isAvailable(on date: Date = Date()) -> Bool {
        guard isSeasonal else { return true }
        return seasonalMonths.contains(Calendar.current.component(.month, from: date))
    }

    func fit(on rig: MascotRig) -> MascotFit { rig.fit(need) }

    var seasonLabel: String? {
        guard isSeasonal else { return nil }
        let f = DateFormatter()
        let names = seasonalMonths.compactMap { m -> String? in
            guard m >= 1, m <= 12 else { return nil }
            return f.shortMonthSymbols[m - 1]
        }
        return names.joined(separator: ", ")
    }
}

// MARK: - Catalog

enum MascotWardrobeCatalog {
    static let all: [MascotWardrobeItem] = build()

    static func item(id: String) -> MascotWardrobeItem? { byID[id] }
    static func items(in slot: MascotWardrobeSlot) -> [MascotWardrobeItem] { bySlot[slot] ?? [] }

    static var freeCount: Int { all.filter { if case .free = $0.unlock { return true }; return false }.count }
    static var premiumCount: Int { all.filter(\.isPremium).count }
    static var earnableCount: Int { all.count - freeCount - premiumCount }

    private static let byID: [String: MascotWardrobeItem] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    private static let bySlot: [MascotWardrobeSlot: [MascotWardrobeItem]] = Dictionary(grouping: all, by: \.slot)

    private static func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    // Shared dye palettes
    private static let brights: [Color] = [c(0.95, 0.33, 0.38), c(0.25, 0.52, 0.95), c(0.30, 0.75, 0.48), c(0.98, 0.78, 0.25), c(0.62, 0.40, 0.92), c(0.98, 0.55, 0.72)]
    private static let pastels: [Color] = [c(0.98, 0.74, 0.80), c(0.70, 0.84, 1.0), c(0.74, 0.93, 0.80), c(1.0, 0.92, 0.66), c(0.84, 0.76, 1.0)]
    private static let neutrals: [Color] = [c(0.20, 0.21, 0.26), c(0.92, 0.90, 0.86), c(0.55, 0.40, 0.28), c(0.40, 0.44, 0.52)]
    private static let metals: [Color] = [c(1.0, 0.80, 0.30), c(0.82, 0.84, 0.90), c(0.92, 0.58, 0.45)]
    private static let hairs: [Color] = [c(0.36, 0.24, 0.16), c(0.14, 0.12, 0.14), c(0.96, 0.82, 0.48), c(0.86, 0.42, 0.20), c(0.98, 0.60, 0.78), c(0.42, 0.62, 0.98), c(0.66, 0.48, 0.94), c(0.50, 0.88, 0.76)]

    private static func it(
        _ id: String, _ slot: MascotWardrobeSlot, _ name: String, _ blurb: String,
        _ rarity: MascotWardrobeRarity, _ style: String, _ unlock: MascotUnlock = .free,
        pattern: MascotPattern = .plain, dyes: [Color], need: MascotNeed? = nil, months: [Int] = []
    ) -> MascotWardrobeItem {
        MascotWardrobeItem(id: id, slot: slot, name: name, blurb: blurb, rarity: rarity, style: style,
                           pattern: pattern, dyes: dyes, unlock: unlock, need: need ?? slot.defaultNeed, seasonalMonths: months)
    }

    private static func build() -> [MascotWardrobeItem] {
        var x: [MascotWardrobeItem] = []

        // Hats (30)
        x += [
            it("hat.beanie", .hat, "Knit beanie", "Chunky rib knit that keeps ideas warm.", .common, "beanie", pattern: .knit, dyes: brights + neutrals),
            it("hat.pombeanie", .hat, "Pom beanie", "A beanie with a bouncy pom-pom.", .common, "pombeanie", pattern: .stripes, dyes: brights),
            it("hat.cap", .hat, "Ball cap", "Six panels, one curved bill.", .common, "cap", dyes: brights + neutrals),
            it("hat.backcap", .hat, "Backwards cap", "Worn the cool way round.", .common, "backcap", dyes: brights + neutrals),
            it("hat.bucket", .hat, "Bucket hat", "Soft cotton with stitched brim.", .common, "bucket", pattern: .check, dyes: pastels + neutrals),
            it("hat.beret", .hat, "Beret", "For the artist in every draft.", .uncommon, "beret", dyes: [c(0.70, 0.14, 0.22), c(0.18, 0.20, 0.30), c(0.95, 0.60, 0.25)]),
            it("hat.flowerclip", .hat, "Flower clip", "A fresh bloom tucked to one side.", .common, "flowerclip", dyes: [c(1.0, 0.55, 0.72), c(1.0, 0.85, 0.30), c(0.62, 0.70, 1.0), c(1, 1, 1)]),
            it("hat.bigbow", .hat, "Big bow", "Satin ribbon tied with love.", .common, "bigbow", pattern: .dots, dyes: brights + pastels),
            it("hat.headphones", .hat, "Headphones", "Cushioned cups for lo-fi focus.", .uncommon, "headphones", dyes: neutrals + brights),
            it("hat.bandana", .hat, "Bandana", "Tied tight, tails flying.", .common, "bandana", pattern: .dots, dyes: brights),
            it("hat.chef", .hat, "Chef’s toque", "Pleated, puffy and very serious.", .common, "chef", dyes: [c(0.98, 0.98, 0.98)]),
            it("hat.party", .hat, "Party cone", "Every day is a celebration.", .common, "party", pattern: .dots, dyes: brights),
            it("hat.catbeanie", .hat, "Cat-ear beanie", "Two pointy ears, extra cute.", .uncommon, "catbeanie", .coins(120), pattern: .knit, dyes: pastels + neutrals),
            it("hat.propeller", .hat, "Propeller cap", "Spins when you’re thinking hard.", .uncommon, "propeller", .coins(80), dyes: brights),
            it("hat.halo", .hat, "Halo", "A gentle glow for good vibes only.", .rare, "halo", .coins(150), dyes: [c(1.0, 0.88, 0.40), c(0.80, 0.92, 1.0), c(1.0, 0.70, 0.85)]),
            it("hat.bdaycrown", .hat, "Birthday crown", "Paper crown with tiny candles.", .epic, "bdaycrown", .achievement("birthday"), dyes: [c(1.0, 0.80, 0.30), c(0.98, 0.55, 0.72)]),
            it("hat.tophat", .hat, "Top hat", "Satin finish, impeccable manners.", .rare, "tophat", .premium, dyes: [c(0.12, 0.12, 0.16), c(0.45, 0.10, 0.18), c(0.92, 0.92, 0.95)]),
            it("hat.cowboy", .hat, "Cowboy hat", "Wide brim for wide horizons.", .rare, "cowboy", .premium, dyes: [c(0.62, 0.42, 0.26), c(0.18, 0.16, 0.16), c(0.95, 0.90, 0.80)]),
            it("hat.fedora", .hat, "Fedora", "Pinched crown and a crisp band.", .uncommon, "fedora", .premium, dyes: [c(0.30, 0.30, 0.34), c(0.55, 0.40, 0.28), c(0.20, 0.24, 0.40)]),
            it("hat.tricorn", .hat, "Captain’s tricorn", "Gold trim for the high seas.", .epic, "tricorn", .premium, dyes: [c(0.14, 0.14, 0.18), c(0.40, 0.12, 0.16)]),
            it("hat.wizard", .hat, "Wizard hat", "Star-dusted and slightly bent.", .epic, "wizard", .premium, pattern: .stars, dyes: [c(0.30, 0.22, 0.62), c(0.12, 0.20, 0.45), c(0.55, 0.15, 0.40)]),
            it("hat.tiara", .hat, "Gem tiara", "Faceted gems that catch the light.", .epic, "tiara", .premium, dyes: metals),
            it("hat.crown", .hat, "Royal crown", "Gold, rubies and a velvet cushion.", .legendary, "crown", .premium, dyes: metals),
            it("hat.laurel", .hat, "Laurel wreath", "For champions of the comment section.", .rare, "laurel", .premium, dyes: [c(0.40, 0.70, 0.35), c(1.0, 0.80, 0.30)]),
            it("hat.horns", .hat, "Little horns", "Mischief, but make it cute.", .rare, "horns", .premium, dyes: [c(0.70, 0.18, 0.22), c(0.20, 0.18, 0.22), c(0.95, 0.90, 0.80)]),
            it("hat.unicorn", .hat, "Unicorn horn", "Pearlescent spiral of pure magic.", .legendary, "unicorn", .premium, dyes: [c(0.98, 0.86, 1.0), c(1.0, 0.85, 0.50), c(0.80, 0.95, 1.0)]),
            it("hat.mushroom", .hat, "Mushroom cap", "Spotty, springy, forest-fresh.", .rare, "mushroom", .premium, dyes: [c(0.90, 0.22, 0.24), c(0.62, 0.42, 0.85), c(0.95, 0.65, 0.25)]),
            it("hat.frog", .hat, "Froggy hat", "Big friendly eyes on top.", .uncommon, "froghat", .premium, dyes: [c(0.40, 0.78, 0.38), c(0.98, 0.70, 0.80)]),
            it("hat.grad", .hat, "Graduation cap", "Tassel swings when you nod.", .uncommon, "gradcap", .premium, dyes: [c(0.14, 0.14, 0.18), c(0.20, 0.30, 0.65)]),
            it("hat.sailor", .hat, "Sailor cap", "Crisp white with a navy band.", .common, "sailor", .premium, dyes: [c(0.97, 0.97, 0.98)]),
        ]

        // Hair (12)
        x += [
            it("hair.bob", .hair, "Bob", "Neat, swingy and sleek.", .common, "bob", dyes: hairs),
            it("hair.spiky", .hair, "Spiky", "Gelled to the sky.", .common, "spiky", dyes: hairs),
            it("hair.topbun", .hair, "Top bun", "Effortless, slightly messy.", .common, "topbun", dyes: hairs),
            it("hair.swoop", .hair, "Side swoop", "A dramatic sweep of fringe.", .common, "swoop", dyes: hairs),
            it("hair.pigtails", .hair, "Pigtails", "Two bouncy tails with ties.", .uncommon, "pigtails", .coins(100), dyes: hairs),
            it("hair.ponytail", .hair, "Ponytail", "Swishes when you move.", .uncommon, "ponytail", .premium, dyes: hairs),
            it("hair.afro", .hair, "Cloud puff", "Big, soft, glorious volume.", .rare, "afro", .premium, dyes: hairs),
            it("hair.mohawk", .hair, "Mohawk", "A bold crest of spikes.", .rare, "mohawk", .premium, dyes: hairs),
            it("hair.twinbuns", .hair, "Twin buns", "Two buns, double the charm.", .uncommon, "twinbuns", .premium, dyes: hairs),
            it("hair.waves", .hair, "Long waves", "Flowing waves down to the toes.", .epic, "waves", .premium, dyes: hairs),
            it("hair.braid", .hair, "Side braid", "A woven braid over the shoulder.", .rare, "braid", .premium, dyes: hairs),
            it("hair.curlybob", .hair, "Curly bob", "Bouncy ringlets all round.", .uncommon, "curlybob", .premium, dyes: hairs),
        ]

        // Face (18)
        x += [
            it("face.roundglasses", .face, "Round glasses", "Thin frames, big ideas.", .common, "roundglasses", dyes: neutrals + metals),
            it("face.blush", .face, "Rosy blush", "A soft, happy flush.", .common, "blush", dyes: [c(1.0, 0.55, 0.62), c(1.0, 0.70, 0.50), c(0.90, 0.55, 0.95)]),
            it("face.freckles", .face, "Freckles", "Sun-kissed speckles.", .common, "freckles", dyes: [c(0.72, 0.45, 0.28), c(0.95, 0.55, 0.40)]),
            it("face.bandaid", .face, "Band-aid", "Brave little bandage.", .common, "bandaid", dyes: [c(0.98, 0.84, 0.62), c(0.98, 0.70, 0.80), c(0.70, 0.84, 1.0)]),
            it("face.whiskers", .face, "Whiskers", "Painted-on kitty whiskers.", .common, "whiskers", dyes: [c(0.25, 0.22, 0.24), c(1, 1, 1)]),
            it("face.starpaint", .face, "Star face paint", "A glittery star on the cheek.", .common, "starpaint", dyes: [c(1.0, 0.82, 0.30), c(0.40, 0.70, 1.0), c(1.0, 0.50, 0.70)]),
            it("face.squareglasses", .face, "Square glasses", "Bold frames for bold takes.", .uncommon, "squareglasses", .coins(60), dyes: neutrals + brights),
            it("face.heartshades", .face, "Heart shades", "Tinted hearts, see-through charm.", .uncommon, "heartshades", .coins(90), dyes: [c(1.0, 0.35, 0.55), c(0.62, 0.40, 0.92), c(0.20, 0.20, 0.24)]),
            it("face.starshades", .face, "Star shades", "Pop-star energy.", .rare, "starshades", .premium, dyes: [c(1.0, 0.82, 0.30), c(0.40, 0.70, 1.0)]),
            it("face.aviators", .face, "Aviators", "Gold rims, gradient lenses.", .rare, "aviators", .premium, dyes: metals),
            it("face.monocle", .face, "Monocle", "Polished lens on a fine chain.", .rare, "monocle", .premium, dyes: metals),
            it("face.masquerade", .face, "Masquerade mask", "Sequins around the eyes.", .epic, "masquerade", .premium, dyes: [c(0.62, 0.30, 0.92), c(0.12, 0.12, 0.16), c(1.0, 0.75, 0.30)]),
            it("face.visor", .face, "Cyber visor", "Holographic, see-through band.", .epic, "visor", .premium, dyes: [c(0.25, 0.95, 0.85), c(1.0, 0.35, 0.70)]),
            it("face.3d", .face, "3D glasses", "Red and cyan, retro cinema.", .uncommon, "glasses3d", .premium, dyes: [c(0.97, 0.97, 0.97)]),
            it("face.heartpaint", .face, "Heart face paint", "Tiny heart on the cheek.", .common, "heartpaint", .premium, dyes: [c(1.0, 0.35, 0.50), c(0.62, 0.40, 0.92)]),
            it("face.glitter", .face, "Glitter cheeks", "Sparkles that twinkle.", .rare, "glitter", .premium, dyes: [c(1.0, 0.88, 0.95), c(0.80, 0.92, 1.0), c(1.0, 0.90, 0.55)]),
            it("face.teargem", .face, "Tear gem", "A faceted gem under one eye.", .epic, "teargem", .premium, dyes: [c(0.40, 0.75, 1.0), c(1.0, 0.40, 0.65), c(0.70, 0.45, 1.0)]),
            it("face.nerdtape", .face, "Taped glasses", "Lovingly repaired frames.", .uncommon, "tapedglasses", .premium, dyes: neutrals),
        ]

        // Tops (18)
        x += [
            it("top.tee", .top, "Tee", "Soft cotton crew neck.", .common, "tee", dyes: brights + neutrals),
            it("top.stripetee", .top, "Striped tee", "Breton stripes, effortless.", .common, "tee", pattern: .stripes, dyes: brights + neutrals),
            it("top.hoodie", .top, "Hoodie", "Cosy hood, drawstrings, kangaroo pocket.", .common, "hoodie", dyes: brights + neutrals),
            it("top.sweater", .top, "Knit sweater", "Cable knit for chilly days.", .common, "sweater", pattern: .knit, dyes: brights + pastels),
            it("top.tank", .top, "Tank top", "Sporty and breezy.", .common, "tank", dyes: brights),
            it("top.polo", .top, "Polo", "Collared, buttoned, smart.", .common, "polo", dyes: pastels + neutrals),
            it("top.overalls", .top, "Overalls", "Denim bib with brass buttons.", .common, "overalls", dyes: [c(0.30, 0.45, 0.75), c(0.85, 0.55, 0.30), c(0.95, 0.60, 0.72)]),
            it("top.jersey", .top, "Team jersey", "Number one fan.", .uncommon, "jersey", .coins(100), pattern: .stripes, dyes: brights),
            it("top.flannel", .top, "Flannel shirt", "Classic plaid, buttoned up.", .uncommon, "flannel", .coins(120), pattern: .plaid, dyes: brights),
            it("top.turtleneck", .top, "Turtleneck", "Ribbed and refined.", .uncommon, "turtleneck", .premium, dyes: neutrals + brights),
            it("top.sailor", .top, "Sailor top", "Square collar, navy trim.", .rare, "sailortop", .premium, dyes: [c(0.97, 0.97, 0.98), c(0.20, 0.28, 0.55)]),
            it("top.hawaiian", .top, "Island shirt", "Loud florals, relaxed fit.", .rare, "islandshirt", .premium, pattern: .floral, dyes: [c(0.20, 0.65, 0.75), c(0.95, 0.45, 0.35), c(0.98, 0.80, 0.30)]),
            it("top.tux", .top, "Tuxedo shirt", "Pleated front, black studs.", .epic, "tux", .premium, dyes: [c(0.98, 0.98, 0.98)]),
            it("top.robe", .top, "Wrap robe", "Silky crossover wrap with sash.", .rare, "robe", .premium, pattern: .floral, dyes: [c(0.85, 0.30, 0.45), c(0.25, 0.30, 0.55), c(0.95, 0.80, 0.85)]),
            it("top.armor", .top, "Knight armor", "Polished plates, gold rivets.", .legendary, "armor", .premium, dyes: [c(0.78, 0.80, 0.86), c(1.0, 0.80, 0.35)]),
            it("top.herosuit", .top, "Hero suit", "Emblem on the chest, cape-ready.", .epic, "herosuit", .premium, dyes: [c(0.20, 0.35, 0.85), c(0.85, 0.18, 0.22), c(0.15, 0.15, 0.18)]),
            it("top.dress", .top, "Party dress", "Bodice with a sparkly waistband.", .rare, "dresstop", .premium, pattern: .dots, dyes: pastels + brights),
            it("top.spacesuit", .top, "Space suit", "Control panel and mission patch.", .epic, "spacesuit", .premium, dyes: [c(0.95, 0.95, 0.97), c(0.98, 0.60, 0.25)]),
        ]

        // Outerwear (12)
        x += [
            it("out.cardigan", .outerwear, "Cardigan", "Open knit with wooden buttons.", .common, "cardigan", pattern: .knit, dyes: pastels + neutrals),
            it("out.vest", .outerwear, "Puffer vest", "Quilted and warm.", .common, "vest", dyes: brights + neutrals),
            it("out.raincoat", .outerwear, "Raincoat", "Glossy, sunny-yellow slicker.", .common, "raincoat", dyes: [c(1.0, 0.85, 0.25), c(0.95, 0.35, 0.35), c(0.30, 0.70, 0.95)]),
            it("out.denim", .outerwear, "Denim jacket", "Stonewashed with chest pockets.", .uncommon, "denim", .coins(140), dyes: [c(0.35, 0.50, 0.78), c(0.18, 0.22, 0.35), c(0.85, 0.85, 0.88)]),
            it("out.puffer", .outerwear, "Puffer jacket", "Big puffy quilting.", .uncommon, "puffer", .premium, dyes: brights + neutrals),
            it("out.blazer", .outerwear, "Blazer", "Sharp lapels, pocket square.", .rare, "blazer", .premium, dyes: [c(0.18, 0.20, 0.30), c(0.70, 0.18, 0.25), c(0.85, 0.80, 0.70)]),
            it("out.leather", .outerwear, "Biker jacket", "Zips, studs and attitude.", .rare, "leather", .premium, dyes: [c(0.12, 0.12, 0.14), c(0.45, 0.25, 0.18)]),
            it("out.labcoat", .outerwear, "Lab coat", "For very important experiments.", .uncommon, "labcoat", .premium, dyes: [c(0.97, 0.97, 0.98)]),
            it("out.varsity", .outerwear, "Varsity jacket", "Contrast sleeves, big letter.", .rare, "varsity", .premium, dyes: brights),
            it("out.trench", .outerwear, "Trench coat", "Belted, buttoned, mysterious.", .rare, "trench", .premium, dyes: [c(0.80, 0.68, 0.48), c(0.25, 0.25, 0.28)]),
            it("out.royalrobe", .outerwear, "Royal robe", "Velvet with ermine trim.", .legendary, "royalrobe", .premium, dyes: [c(0.50, 0.15, 0.55), c(0.70, 0.12, 0.18), c(0.15, 0.25, 0.60)]),
            it("out.tabard", .outerwear, "Knight’s tabard", "Heraldic tunic with crest.", .epic, "tabard", .premium, dyes: [c(0.20, 0.35, 0.80), c(0.80, 0.18, 0.22)]),
        ]

        // Bottoms (8)
        x += [
            it("bot.shorts", .bottom, "Shorts", "Comfy cotton shorts.", .common, "shorts", dyes: brights + neutrals),
            it("bot.skirt", .bottom, "A-line skirt", "Twirls beautifully.", .common, "skirt", dyes: brights + pastels, need: .frill),
            it("bot.tutu", .bottom, "Tutu", "Layers of airy tulle.", .common, "tutu", dyes: pastels, need: .frill),
            it("bot.jeans", .bottom, "Jeans", "Classic five-pocket denim.", .uncommon, "jeans", .premium, dyes: [c(0.30, 0.45, 0.75), c(0.18, 0.20, 0.28)], need: .legs),
            it("bot.plaidskirt", .bottom, "Plaid skirt", "Pleated tartan.", .uncommon, "pleated", .premium, pattern: .plaid, dyes: brights, need: .frill),
            it("bot.cargo", .bottom, "Cargo shorts", "So many pockets.", .uncommon, "cargo", .premium, dyes: [c(0.55, 0.55, 0.38), c(0.40, 0.44, 0.52)]),
            it("bot.sparkleskirt", .bottom, "Sparkle skirt", "Sequins that shimmer.", .epic, "sparkleskirt", .premium, dyes: metals + pastels, need: .frill),
            it("bot.flowerskirt", .bottom, "Petal skirt", "A skirt made of petals.", .rare, "petalskirt", .premium, dyes: pastels, need: .frill),
        ]

        // Shoes (8)
        x += [
            it("shoe.sneakers", .shoes, "Sneakers", "Laced-up and ready to go.", .common, "sneakers", dyes: [c(0.97, 0.97, 0.98)] + brights),
            it("shoe.rainboots", .shoes, "Rain boots", "Puddle-proof and glossy.", .common, "rainboots", dyes: [c(1.0, 0.85, 0.25), c(0.95, 0.35, 0.35), c(0.30, 0.70, 0.95)]),
            it("shoe.slippers", .shoes, "Bunny slippers", "Fluffy ears on each toe.", .common, "slippers", dyes: [c(0.98, 0.92, 0.94), c(0.98, 0.75, 0.82)]),
            it("shoe.boots", .shoes, "Hiking boots", "Sturdy soles, red laces.", .uncommon, "boots", .coins(90), dyes: [c(0.55, 0.38, 0.24), c(0.20, 0.20, 0.22)]),
            it("shoe.lightup", .shoes, "Light-up kicks", "Soles glow with every step.", .rare, "lightup", .premium, dyes: brights),
            it("shoe.rollers", .shoes, "Roller skates", "Rainbow wheels, smooth rides.", .rare, "rollers", .premium, dyes: brights),
            it("shoe.rocket", .shoes, "Rocket boots", "Little flames, big lift.", .legendary, "rocketboots", .premium, dyes: [c(0.80, 0.84, 0.92), c(0.95, 0.35, 0.35)]),
            it("shoe.crystal", .shoes, "Crystal slippers", "Glass-like and gleaming.", .epic, "crystal", .premium, dyes: [c(0.80, 0.92, 1.0), c(1.0, 0.85, 0.95)]),
        ]

        // Accessories (14)
        x += [
            it("acc.scarf", .accessory, "Knit scarf", "Wraps the neck, tail flutters.", .common, "scarf", pattern: .stripes, dyes: brights),
            it("acc.bowtie", .accessory, "Bow tie", "Dapper and dotty.", .common, "bowtie", pattern: .dots, dyes: brights + neutrals),
            it("acc.necklace", .accessory, "Pendant", "A fine chain with a gem.", .common, "pendant", dyes: metals),
            it("acc.starpin", .accessory, "Star pin", "Enamel star badge.", .common, "starpin", dyes: [c(1.0, 0.82, 0.30), c(0.40, 0.70, 1.0)]),
            it("acc.heartpin", .accessory, "Heart pin", "Enamel heart badge.", .common, "heartpin", dyes: [c(1.0, 0.35, 0.50), c(0.98, 0.70, 0.80)]),
            it("acc.bell", .accessory, "Bell collar", "Jingles softly.", .common, "bellcollar", dyes: brights),
            it("acc.daisy", .accessory, "Daisy chain", "Handmade from the meadow.", .common, "daisychain", dyes: [c(1, 1, 1), c(1.0, 0.85, 0.40)]),
            it("acc.firstpin", .accessory, "First Comment pin", "Earned for your first comment.", .rare, "firstpin", .achievement("first_comment"), dyes: [c(0.21, 0.61, 0.67)]),
            it("acc.satchel", .accessory, "Satchel", "Cross-body bag for snacks.", .uncommon, "satchel", .coins(110), dyes: [c(0.60, 0.40, 0.25)] + brights),
            it("acc.necktie", .accessory, "Necktie", "Business on top.", .common, "necktie", .coins(70), pattern: .stripes, dyes: brights + neutrals),
            it("acc.pearls", .accessory, "Pearl necklace", "Lustrous pearls.", .rare, "pearls", .premium, dyes: [c(0.98, 0.96, 0.94), c(0.95, 0.85, 0.90)]),
            it("acc.medal", .accessory, "Gold medal", "First place in being lovely.", .epic, "medal", .premium, dyes: metals),
            it("acc.goldchain", .accessory, "Gold chain", "Chunky links, big shine.", .epic, "goldchain", .premium, dyes: metals),
            it("acc.amulet", .accessory, "Gem amulet", "Glows with ancient power.", .legendary, "amulet", .premium, dyes: [c(0.40, 0.75, 1.0), c(1.0, 0.35, 0.50), c(0.40, 0.90, 0.55)]),
        ]

        // Held (14)
        x += [
            it("held.balloon", .held, "Balloon", "Floats on a curly string.", .common, "balloon", dyes: brights),
            it("held.lollipop", .held, "Lollipop", "Swirly and sweet.", .common, "lollipop", dyes: brights),
            it("held.flower", .held, "Bouquet", "Three blooms, wrapped.", .common, "bouquet", dyes: pastels + brights),
            it("held.icecream", .held, "Ice cream", "Two scoops on a waffle cone.", .common, "icecream", dyes: [c(0.98, 0.72, 0.80), c(0.70, 0.90, 0.78), c(0.55, 0.36, 0.25), c(0.98, 0.94, 0.82)]),
            it("held.book", .held, "Storybook", "A good read.", .common, "book", dyes: brights),
            it("held.coffee", .held, "Coffee", "Steaming, with a sleeve.", .common, "coffee", .coins(60), dyes: [c(0.95, 0.95, 0.95), c(0.30, 0.65, 0.45)]),
            it("held.boba", .held, "Boba tea", "Chewy pearls, big straw.", .uncommon, "boba", .coins(80), dyes: [c(0.85, 0.70, 0.55), c(0.75, 0.62, 0.90), c(0.60, 0.85, 0.60)]),
            it("held.wand", .held, "Star wand", "Sprinkles sparkles.", .rare, "wand", .premium, dyes: [c(0.80, 0.60, 1.0), c(1.0, 0.70, 0.85)]),
            it("held.umbrella", .held, "Umbrella", "Keeps the drizzle off.", .uncommon, "umbrella", .premium, pattern: .dots, dyes: brights),
            it("held.sword", .held, "Knight’s sword", "Polished steel, gold hilt.", .epic, "sword", .premium, dyes: [c(0.82, 0.85, 0.92)]),
            it("held.lantern", .held, "Lantern", "A warm, flickering glow.", .rare, "lantern", .premium, dyes: [c(1.0, 0.70, 0.30), c(0.55, 0.85, 1.0)]),
            it("held.brush", .held, "Paintbrush", "Dripping with colour.", .uncommon, "paintbrush", .premium, dyes: brights),
            it("held.sparkler", .held, "Sparkler", "Fizzing little fireworks.", .rare, "sparkler", .premium, dyes: [c(1.0, 0.85, 0.40)]),
            it("held.trophy", .held, "Trophy", "Gleaming gold cup.", .epic, "trophy", .premium, dyes: metals),
        ]

        // Back (12)
        x += [
            it("back.backpack", .back, "Backpack", "Straps and a front pocket.", .common, "backpack", dyes: brights + neutrals),
            it("back.herocape", .back, "Hero cape", "Flows in the wind.", .common, "herocape", dyes: brights),
            it("back.streakcape", .back, "Streak cape", "Earned with a 7-day streak.", .epic, "streakcape", .achievement("streak_7"), dyes: [c(1.0, 0.55, 0.20)]),
            it("back.butterfly", .back, "Butterfly wings", "Patterned and fluttery.", .rare, "butterfly", .coins(200), dyes: [c(0.98, 0.60, 0.25), c(0.40, 0.70, 1.0), c(0.95, 0.45, 0.75)]),
            it("back.fairy", .back, "Fairy wings", "Iridescent and delicate.", .epic, "fairy", .premium, dyes: [c(0.80, 0.92, 1.0), c(1.0, 0.85, 0.95), c(0.85, 1.0, 0.88)]),
            it("back.angel", .back, "Angel wings", "Soft layered feathers.", .legendary, "angel", .premium, dyes: [c(0.98, 0.98, 1.0), c(1.0, 0.92, 0.70)]),
            it("back.bat", .back, "Bat wings", "Scalloped and spooky.", .rare, "batwings", .premium, dyes: [c(0.30, 0.18, 0.40), c(0.15, 0.15, 0.18)]),
            it("back.dragon", .back, "Dragon wings", "Bony struts, leathery spans.", .legendary, "dragonwings", .premium, dyes: [c(0.30, 0.65, 0.40), c(0.80, 0.22, 0.20), c(0.30, 0.40, 0.80)]),
            it("back.royalcape", .back, "Royal cape", "Velvet with ermine trim.", .epic, "royalcape", .premium, dyes: [c(0.50, 0.15, 0.55), c(0.70, 0.12, 0.18)]),
            it("back.wizardcape", .back, "Starry cloak", "The night sky, stitched.", .epic, "wizardcape", .premium, pattern: .stars, dyes: [c(0.15, 0.18, 0.40), c(0.30, 0.15, 0.40)]),
            it("back.jetpack", .back, "Jetpack", "Twin tanks, real flames.", .legendary, "jetpack", .premium, dyes: [c(0.70, 0.74, 0.82), c(0.95, 0.40, 0.30)]),
            it("back.shell", .back, "Turtle shell", "Patterned, protective, portable.", .rare, "shell", .premium, dyes: [c(0.45, 0.65, 0.35), c(0.75, 0.55, 0.30)]),
        ]

        // Auras (12)
        x += [
            it("aura.sparkles", .aura, "Sparkle orbit", "Twinkles that circle you.", .common, "sparkles", dyes: [c(1.0, 0.90, 0.45), c(0.70, 0.90, 1.0), c(1.0, 0.70, 0.90)]),
            it("aura.hearts", .aura, "Floating hearts", "Love, rising gently.", .common, "hearts", dyes: [c(1.0, 0.45, 0.60), c(0.80, 0.55, 1.0)]),
            it("aura.notes", .aura, "Music notes", "Humming a little tune.", .common, "notes", dyes: [c(0.55, 0.45, 0.95), c(0.25, 0.65, 0.95)]),
            it("aura.bubbles", .aura, "Bubbles", "Glossy bubbles drifting up.", .common, "bubbles", dyes: [c(0.65, 0.88, 1.0), c(1.0, 0.80, 0.95)]),
            it("aura.zzz", .aura, "Sleepy Zs", "For the dreamers.", .common, "zzz", dyes: [c(0.70, 0.75, 0.95)]),
            it("aura.heartburst", .aura, "Heart burst", "Earned with 10 reactions.", .epic, "heartburst", .achievement("reactions_10"), dyes: [c(1.0, 0.35, 0.55)]),
            it("aura.petals", .aura, "Petal breeze", "Blossoms drifting by.", .uncommon, "petals", .coins(100), dyes: [c(1.0, 0.75, 0.85), c(1.0, 0.90, 0.95)]),
            it("aura.raincloud", .aura, "Rain cloud", "A personal little drizzle.", .uncommon, "raincloud", .premium, dyes: [c(0.55, 0.60, 0.72)]),
            it("aura.flames", .aura, "Flame ring", "Burning bright.", .rare, "flamering", .premium, dyes: [c(1.0, 0.55, 0.20), c(0.40, 0.70, 1.0)]),
            it("aura.rainbow", .aura, "Rainbow arc", "Every colour, all at once.", .rare, "rainbow", .premium, dyes: [c(1, 1, 1)]),
            it("aura.galaxy", .aura, "Galaxy", "A swirling pocket universe.", .legendary, "galaxy", .premium, dyes: [c(0.45, 0.35, 0.95), c(0.95, 0.35, 0.70)]),
            it("aura.lightning", .aura, "Lightning", "Crackling energy.", .epic, "lightning", .premium, dyes: [c(1.0, 0.92, 0.35), c(0.55, 0.85, 1.0)]),
        ]

        // Pets (10)
        x += [
            it("pet.chick", .pet, "Chick", "Peeps and hops beside you.", .common, "chick", dyes: [c(1.0, 0.88, 0.35)]),
            it("pet.snail", .pet, "Snail", "Slow, steady, adorable.", .common, "snail", dyes: [c(0.85, 0.55, 0.35), c(0.60, 0.50, 0.90)]),
            it("pet.kitty", .pet, "Kitty", "Curious little cat.", .uncommon, "kitty", .coins(250), dyes: [c(0.70, 0.70, 0.75), c(0.98, 0.70, 0.40), c(0.20, 0.20, 0.22)]),
            it("pet.puppy", .pet, "Puppy", "Floppy ears, wagging tail.", .uncommon, "puppy", .coins(250), dyes: [c(0.75, 0.55, 0.35), c(0.95, 0.92, 0.88)]),
            it("pet.bunny", .pet, "Bunny", "A tiny hopping friend.", .uncommon, "bunnypet", .premium, dyes: [c(0.98, 0.97, 0.97), c(0.80, 0.70, 0.62)]),
            it("pet.bee", .pet, "Bumblebee", "Buzzes about.", .rare, "bee", .premium, dyes: [c(1.0, 0.82, 0.25)]),
            it("pet.ghost", .pet, "Ghostie", "Boo! (Friendly.)", .rare, "ghostie", .premium, dyes: [c(0.97, 0.97, 1.0)]),
            it("pet.slime", .pet, "Slime", "Jiggly and glossy.", .rare, "slime", .premium, dyes: [c(0.45, 0.90, 0.55), c(0.55, 0.70, 1.0), c(1.0, 0.55, 0.75)]),
            it("pet.fish", .pet, "Fishbowl", "A goldfish on tour.", .epic, "fishbowl", .premium, dyes: [c(1.0, 0.55, 0.20)]),
            it("pet.dragon", .pet, "Dragonling", "A pocket-sized dragon.", .legendary, "dragonling", .premium, dyes: [c(0.40, 0.75, 0.45), c(0.85, 0.30, 0.30), c(0.45, 0.50, 0.90)]),
        ]

        // Scenes (12)
        x += [
            it("bg.soft", .background, "Soft gradient", "Calm two-tone glow.", .common, "soft", dyes: pastels + brights),
            it("bg.meadow", .background, "Meadow", "Rolling hills and flowers.", .common, "meadow", dyes: [c(0.55, 0.80, 0.40)]),
            it("bg.night", .background, "Starry night", "Moonlight and twinkles.", .common, "night", dyes: [c(0.10, 0.12, 0.30)]),
            it("bg.sunset", .background, "Sunset", "Golden hour, every hour.", .common, "sunset", dyes: [c(1.0, 0.55, 0.40)]),
            it("bg.beach", .background, "Beach", "Waves and warm sand.", .uncommon, "beach", .coins(150), dyes: [c(0.35, 0.75, 0.90)]),
            it("bg.room", .background, "Cozy room", "Window, plant, warm light.", .rare, "room", .premium, dyes: [c(0.95, 0.85, 0.70), c(0.75, 0.85, 0.95)]),
            it("bg.space", .background, "Deep space", "Nebulae and a ringed planet.", .epic, "space", .premium, dyes: [c(0.30, 0.20, 0.60)]),
            it("bg.sakura", .background, "Sakura", "Blossoms on the breeze.", .rare, "sakura", .premium, dyes: [c(1.0, 0.80, 0.88)]),
            it("bg.underwater", .background, "Underwater", "Light rays and seaweed.", .rare, "underwater", .premium, dyes: [c(0.15, 0.45, 0.75)]),
            it("bg.city", .background, "City lights", "Skyline at dusk.", .rare, "city", .premium, dyes: [c(0.35, 0.25, 0.55)]),
            it("bg.candy", .background, "Candyland", "Lollipop trees and cotton clouds.", .epic, "candy", .premium, dyes: [c(1.0, 0.80, 0.90)]),
            it("bg.neon", .background, "Neon grid", "Retro synth horizon.", .legendary, "neon", .premium, dyes: [c(0.95, 0.30, 0.80)]),
        ]

        // Seasonal (14)
        x += [
            it("sea.pumpkin", .seasonal, "Pumpkin hat", "Ribbed and spooky-cute.", .uncommon, "pumpkin", months: [10]).with(dyes: [c(0.98, 0.52, 0.15)]),
            it("sea.spookycape", .seasonal, "Spooky cape", "High collar, swishy hem.", .uncommon, "spookycape", need: .back, months: [10]).with(dyes: [c(0.15, 0.12, 0.18), c(0.40, 0.15, 0.45)]),
            it("sea.witch", .seasonal, "Witch hat", "Bent tip, buckle band.", .epic, "witch", .premium, months: [10]).with(dyes: [c(0.18, 0.12, 0.25), c(0.35, 0.20, 0.50)]),
            it("sea.candy", .seasonal, "Candy swirl", "Sweets orbiting you.", .rare, "candyaura", .premium, need: .aura, months: [10]).with(dyes: [c(1.0, 0.55, 0.20)]),
            it("sea.santa", .seasonal, "Santa hat", "Fluffy trim and pom.", .uncommon, "santa", months: [12, 1]).with(dyes: [c(0.88, 0.16, 0.20), c(0.20, 0.55, 0.30)]),
            it("sea.antlers", .seasonal, "Reindeer antlers", "With a jingle bell.", .rare, "antlers", .premium, months: [12]).with(dyes: [c(0.55, 0.38, 0.22)]),
            it("sea.snow", .seasonal, "Snowfall", "Gentle flakes at your sides.", .common, "snow", need: .aura, months: [12, 1, 2]).with(dyes: [c(1, 1, 1)]),
            it("sea.winterscarf", .seasonal, "Winter scarf", "Fair-isle knit.", .common, "winterscarf", need: .neck, months: [12, 1, 2]).with(dyes: [c(0.25, 0.50, 0.85), c(0.85, 0.20, 0.25)]),
            it("sea.valwings", .seasonal, "Valentine wings", "Heart-shaped and rosy.", .epic, "valwings", .premium, need: .back, months: [2]).with(dyes: [c(1.0, 0.45, 0.62)]),
            it("sea.bunnyears", .seasonal, "Bunny ears", "Floppy spring ears.", .uncommon, "bunnyears", months: [3, 4]).with(dyes: [c(0.98, 0.92, 0.94), c(0.85, 0.75, 0.62)]),
            it("sea.clover", .seasonal, "Clover crown", "Lucky leaves all round.", .common, "clover", months: [3]).with(dyes: [c(0.30, 0.72, 0.35)]),
            it("sea.sunhat", .seasonal, "Sun hat", "Woven straw, ribbon tie.", .common, "sunhat", months: [6, 7, 8]).with(dyes: [c(0.95, 0.85, 0.55)]),
            it("sea.firework", .seasonal, "Fireworks", "Bursts above your head.", .rare, "fireworks", .premium, need: .aura, months: [7, 11, 12]).with(dyes: [c(1.0, 0.75, 0.25)]),
            it("sea.leaves", .seasonal, "Autumn leaves", "Crunchy leaves drifting.", .common, "leaves", need: .aura, months: [9, 10, 11]).with(dyes: [c(0.95, 0.55, 0.20)]),
        ]
        return x
    }
}

private extension MascotWardrobeItem {
    func with(dyes: [Color]) -> MascotWardrobeItem {
        MascotWardrobeItem(id: id, slot: slot, name: name, blurb: blurb, rarity: rarity, style: style, pattern: pattern,
                           dyes: dyes, unlock: unlock, need: need, seasonalMonths: seasonalMonths)
    }
}

private extension MascotWardrobeCatalog {
    static func it(_ id: String, _ slot: MascotWardrobeSlot, _ name: String, _ blurb: String, _ rarity: MascotWardrobeRarity,
                   _ style: String, _ unlock: MascotUnlock = .free, need: MascotNeed? = nil, months: [Int]) -> MascotWardrobeItem {
        MascotWardrobeItem(id: id, slot: slot, name: name, blurb: blurb, rarity: rarity, style: style, pattern: .plain,
                           dyes: [.gray], unlock: unlock, need: need ?? slot.defaultNeed, seasonalMonths: months)
    }
}

// MARK: - Outfit

struct MascotOutfit: Codable, Equatable, Sendable {
    var items: [String: String]      // slot rawValue → item id
    var dyes: [String: Int] = [:]    // slot rawValue → dye index

    static let empty = MascotOutfit(items: [:])

    init(items: [String: String], dyes: [String: Int] = [:]) {
        self.items = items
        self.dyes = dyes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([String: String].self, forKey: .items) ?? [:]
        dyes = try c.decodeIfPresent([String: Int].self, forKey: .dyes) ?? [:]
    }

    static func solo(_ item: MascotWardrobeItem, dye: Int = 0) -> MascotOutfit {
        MascotOutfit(items: [item.slot.rawValue: item.id], dyes: [item.slot.rawValue: dye])
    }

    func item(for slot: MascotWardrobeSlot) -> MascotWardrobeItem? {
        items[slot.rawValue].flatMap(MascotWardrobeCatalog.item(id:))
    }
    func dye(for slot: MascotWardrobeSlot) -> Int { dyes[slot.rawValue] ?? 0 }
    func color(for slot: MascotWardrobeSlot) -> Color? { item(for: slot)?.dye(dye(for: slot)) }
    func contains(_ item: MascotWardrobeItem) -> Bool { items[item.slot.rawValue] == item.id }

    mutating func equip(_ item: MascotWardrobeItem, dye: Int? = nil) {
        items[item.slot.rawValue] = item.id
        if let dye { dyes[item.slot.rawValue] = dye } else if dyes[item.slot.rawValue] == nil { dyes[item.slot.rawValue] = 0 }
    }
    mutating func unequip(_ slot: MascotWardrobeSlot) {
        items.removeValue(forKey: slot.rawValue)
        dyes.removeValue(forKey: slot.rawValue)
    }
    mutating func clear() { items = [:]; dyes = [:] }

    var isEmpty: Bool { items.isEmpty }
    var equippedIDs: [String] { Array(items.values) }
    var background: MascotWardrobeItem? { item(for: .background) }

    /// Equipped items that can be drawn on this rig (non-fitting ones are hidden, background excluded).
    func wearables(on rig: MascotRig) -> [(item: MascotWardrobeItem, color: Color, fit: MascotFit)] {
        MascotWardrobeSlot.allCases.compactMap { slot in
            guard slot != .background, let item = item(for: slot) else { return nil }
            let fit = item.fit(on: rig)
            guard fit.isWearable else { return nil }
            return (item, item.dye(dye(for: slot)), fit)
        }
    }
}

struct MascotOutfitPreset: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var outfit: MascotOutfit
    var createdAt: Date
}

// MARK: - Wardrobe store (device-local; shaped for later server sync)

@MainActor @Observable
final class MascotWardrobeStore {
    static let shared = MascotWardrobeStore()

    private let outfitKey = "composer.mascot.outfit"
    private let presetsKey = "composer.mascot.outfitPresets"
    private let birthdayOutfitAppliedKey = "composer.mascot.birthdayOutfitDay"

    private(set) var outfit: MascotOutfit
    private(set) var presets: [MascotOutfitPreset]
    private var undoStack: [MascotOutfit] = []

    var canUndo: Bool { !undoStack.isEmpty }

    private init() {
        let d = UserDefaults.standard
        outfit = d.data(forKey: outfitKey).flatMap { try? JSONDecoder().decode(MascotOutfit.self, from: $0) } ?? .empty
        presets = d.data(forKey: presetsKey).flatMap { try? JSONDecoder().decode([MascotOutfitPreset].self, from: $0) } ?? []
        sanitizeOutfit()
    }

    // Ownership
    func owns(_ item: MascotWardrobeItem) -> Bool {
        switch item.unlock {
        case .free: return true
        case .premium: return MascotEntitlements.isPremium
        case .coins, .achievement: return MascotEntitlements.isPremium || MascotProgressStore.shared.owned.contains(item.id)
        }
    }
    func canEquip(_ item: MascotWardrobeItem) -> Bool { owns(item) && item.isAvailable() }

    // Editing
    func equip(_ item: MascotWardrobeItem, dye: Int? = nil) {
        guard canEquip(item) else { return }
        commit { $0.equip(item, dye: dye) }
    }
    func toggle(_ item: MascotWardrobeItem) {
        if outfit.contains(item) { unequip(item.slot) } else { equip(item) }
    }
    func setDye(_ index: Int, for slot: MascotWardrobeSlot) {
        guard outfit.item(for: slot) != nil else { return }
        commit { $0.dyes[slot.rawValue] = index }
    }
    func unequip(_ slot: MascotWardrobeSlot) { commit { $0.unequip(slot) } }
    func clearOutfit() { commit { $0.clear() } }
    func apply(_ next: MascotOutfit) { commit { $0 = next } }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        outfit = last
        persist(); announce()
    }

    /// Random owned items that fit the rig.
    func randomize(for rig: MascotRig) {
        let chances: [MascotWardrobeSlot: Double] = [
            .hat: 0.65, .hair: 0.35, .face: 0.4, .top: 0.6, .outerwear: 0.25, .bottom: 0.3, .shoes: 0.45,
            .accessory: 0.4, .held: 0.35, .back: 0.3, .aura: 0.3, .pet: 0.25, .background: 0.7,
        ]
        var next = MascotOutfit.empty
        for (slot, chance) in chances where Double.random(in: 0...1) < chance {
            let pool = MascotWardrobeCatalog.items(in: slot).filter { canEquip($0) && $0.fit(on: rig) == .fits }
            if let pick = pool.randomElement() { next.equip(pick, dye: Int.random(in: 0..<max(1, pick.dyes.count))) }
        }
        apply(next)
    }

    // Presets
    func savePreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        presets.insert(MascotOutfitPreset(id: UUID().uuidString, name: trimmed.isEmpty ? "Outfit \(presets.count + 1)" : trimmed, outfit: outfit, createdAt: Date()), at: 0)
        persistPresets()
        MascotProgressStore.shared.record(.savedOutfit)
    }
    func applyPreset(_ preset: MascotOutfitPreset) {
        var next = preset.outfit
        for (slot, id) in next.items {
            if let item = MascotWardrobeCatalog.item(id: id), canEquip(item) { continue }
            next.items.removeValue(forKey: slot)
        }
        apply(next)
    }
    func renamePreset(_ preset: MascotOutfitPreset, to name: String) {
        guard let i = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        presets[i].name = name
        persistPresets()
    }
    func deletePreset(_ preset: MascotOutfitPreset) {
        presets.removeAll { $0.id == preset.id }
        persistPresets()
    }

    // Delights
    @discardableResult
    func applyOutfitOfTheDayIfNeeded() -> Bool {
        let key = "composer.mascot.ootd.\(MascotProgressStore.dayKey())"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        UserDefaults.standard.set(true, forKey: key)
        guard outfit.isEmpty else { return false }
        var next = MascotOutfit.empty
        for slot in [MascotWardrobeSlot.hat, .accessory, .aura] {
            if let pick = MascotWardrobeCatalog.items(in: slot).filter({ canEquip($0) && $0.unlock == .free }).randomElement() {
                next.equip(pick, dye: Int.random(in: 0..<max(1, pick.dyes.count)))
            }
        }
        outfit = next
        persist()
        return true
    }

    @discardableResult
    func applyBirthdayOutfitIfNeeded(birthday: DateComponents?) -> Bool {
        guard let birthday, let month = birthday.month, let day = birthday.day else { return false }
        let now = Calendar.current.dateComponents([.month, .day, .year], from: Date())
        guard now.month == month, now.day == day else { return false }
        MascotProgressStore.shared.record(.birthday)
        let stamp = "\(month)-\(day)-\(now.year ?? 0)"
        guard UserDefaults.standard.string(forKey: birthdayOutfitAppliedKey) != stamp else { return false }
        UserDefaults.standard.set(stamp, forKey: birthdayOutfitAppliedKey)
        var next = outfit
        for id in ["hat.bdaycrown", "aura.sparkles", "held.balloon"] {
            if let item = MascotWardrobeCatalog.item(id: id), canEquip(item) { next.equip(item) }
        }
        apply(next)
        return true
    }

    // Internals
    private func commit(_ change: (inout MascotOutfit) -> Void) {
        var next = outfit
        change(&next)
        guard next != outfit else { return }
        undoStack.append(outfit)
        if undoStack.count > 30 { undoStack.removeFirst() }
        outfit = next
        persist(); announce()
    }

    private func sanitizeOutfit() {
        var changed = false
        for (slot, id) in outfit.items {
            guard let item = MascotWardrobeCatalog.item(id: id), item.slot.rawValue == slot, owns(item) else {
                outfit.items.removeValue(forKey: slot)
                outfit.dyes.removeValue(forKey: slot)
                changed = true
                continue
            }
        }
        if changed { persist() }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(outfit) { UserDefaults.standard.set(data, forKey: outfitKey) }
    }
    private func persistPresets() {
        if let data = try? JSONEncoder().encode(presets) { UserDefaults.standard.set(data, forKey: presetsKey) }
    }
    private func announce() {
        NotificationCenter.default.post(name: .mascotOutfitDidChange, object: nil)
    }
}

extension Notification.Name {
    static let mascotOutfitDidChange = Notification.Name("mascotOutfitDidChange")
}

// MARK: - Profile / settings keys

enum MascotProfileSettings {
    static let showOnProfileKey = "composer.mascot.profile.show"
    static let useAsAvatarKey = "composer.mascot.profile.asAvatar"
}
