import SwiftUI

// MARK: - Full-body costumes

/// Original full-body outfits (no trademarked names, logos or emblems). Equipped as one
/// wardrobe item; conflicting slot pieces are parked on the outfit and restored when the
/// costume comes off.
enum MascotCostumeCatalog {
    static let all: [MascotWardrobeItem] = build()

    /// Clothing slots a costume covers while it is worn. Pets, held items, auras and scenes stay.
    static let coveredSlots: [MascotWardrobeSlot] = [
        .hat, .hair, .face, .top, .outerwear, .bottom, .shoes, .accessory, .back, .seasonal,
    ]

    static var ids: [String] { all.map(\.id) }

    private static func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    private static func it(
        _ id: String, _ name: String, _ blurb: String,
        _ rarity: MascotWardrobeRarity, _ style: String, _ unlock: MascotUnlock,
        dyes: [Color]
    ) -> MascotWardrobeItem {
        MascotWardrobeItem(
            id: id, slot: .costume, name: name, blurb: blurb, rarity: rarity, style: style,
            pattern: .plain, dyes: dyes, unlock: unlock, need: .body, seasonalMonths: []
        )
    }

    private static func build() -> [MascotWardrobeItem] {
        [
            it("costume.starbolt", "Starbolt Cape",
               "A caped hero suit with a shining star-bolt on the chest.",
               .rare, "starbolt", .coins(160),
               dyes: [c(0.16, 0.38, 0.86), c(0.82, 0.14, 0.18), c(0.12, 0.14, 0.20)]),
            it("costume.hexweave", "Hexweave Suit",
               "A nimble suit traced with a glowing hex lattice.",
               .rare, "hexweave", .coins(160),
               dyes: [c(0.78, 0.12, 0.18), c(0.12, 0.16, 0.22), c(0.10, 0.42, 0.72)]),
            it("costume.nightveil", "Nightveil",
               "A masked night guardian wrapped in deep indigo.",
               .epic, "nightveil", .coins(220),
               dyes: [c(0.14, 0.14, 0.22), c(0.28, 0.16, 0.40), c(0.10, 0.10, 0.14)]),
            it("costume.solarranger", "Solar Ranger",
               "A space ranger ready for the next orbit.",
               .rare, "solarranger", .coins(180),
               dyes: [c(0.18, 0.42, 0.48), c(0.96, 0.72, 0.22), c(0.86, 0.42, 0.16)]),
            it("costume.pebbleknight", "Pebble Knight",
               "Polished armour and a tiny, proud helm.",
               .uncommon, "pebbleknight", .coins(140),
               dyes: [c(0.62, 0.66, 0.72), c(0.82, 0.64, 0.28), c(0.40, 0.44, 0.50)]),
            it("costume.glimmermage", "Glimmer Mage",
               "A starry robe and a hat full of sparks.",
               .rare, "glimmermage", .coins(180),
               dyes: [c(0.36, 0.22, 0.66), c(0.14, 0.16, 0.32), c(0.86, 0.62, 0.95)]),
            it("costume.tidecaptain", "Tide Captain",
               "A tricorn, a tailored coat and salt-air swagger.",
               .uncommon, "tidecaptain", .coins(130),
               dyes: [c(0.28, 0.18, 0.14), c(0.72, 0.16, 0.16), c(0.14, 0.28, 0.40)]),
            it("costume.shadowstep", "Shadowstep",
               "A quiet wrap for midnight strolls.",
               .rare, "shadowstep", .coins(170),
               dyes: [c(0.12, 0.12, 0.14), c(0.28, 0.10, 0.12), c(0.18, 0.22, 0.28)]),
            it("costume.moonwalker", "Moonwalker",
               "A round-helmet astronaut ready for dust hops.",
               .rare, "moonwalker", .coins(200),
               dyes: [c(0.92, 0.93, 0.95), c(0.30, 0.55, 0.82), c(0.86, 0.62, 0.18)]),
            it("costume.sproutsaur", "Sproutsaur Onesie",
               "A cuddly dino hood and a happy little tail.",
               .common, "sproutsaur", .free,
               dyes: [c(0.36, 0.76, 0.42), c(0.22, 0.58, 0.34), c(0.95, 0.72, 0.28)]),
            it("costume.cottonhop", "Cottonhop Onesie",
               "Floppy bunny ears and a pom-pom tail.",
               .common, "cottonhop", .free,
               dyes: [c(0.98, 0.90, 0.94), c(0.72, 0.82, 0.98), c(1.0, 0.78, 0.86)]),
            it("costume.whisk", "Whisk Kitchen",
               "A toque, kerchief and a very serious apron.",
               .common, "whisk", .free,
               dyes: [c(0.98, 0.98, 0.98), c(0.18, 0.18, 0.20), c(0.86, 0.18, 0.22)]),
            it("costume.emberbrigade", "Ember Brigade",
               "A firefighter coat, helmet and a ready hose.",
               .uncommon, "emberbrigade", .coins(120),
               dyes: [c(0.78, 0.16, 0.14), c(0.18, 0.18, 0.20), c(0.92, 0.62, 0.16)]),
            it("costume.crownlight", "Crownlight Regalia",
               "A tiny crown, an ermine cape and a royal sash.",
               .epic, "crownlight", .coins(240),
               dyes: [c(0.46, 0.18, 0.52), c(0.96, 0.78, 0.28), c(0.86, 0.14, 0.22)]),
            it("costume.cluecoat", "Cluecoat",
               "A trench, a brim and a knowing magnifying glass.",
               .uncommon, "cluecoat", .coins(110),
               dyes: [c(0.42, 0.32, 0.22), c(0.18, 0.16, 0.14), c(0.72, 0.62, 0.40)]),
            it("costume.voltframe", "Voltframe",
               "A friendly robot shell with bright bolts.",
               .rare, "voltframe", .coins(190),
               dyes: [c(0.72, 0.76, 0.82), c(0.20, 0.72, 0.78), c(0.96, 0.78, 0.22)]),
            it("costume.auroradiver", "Aurora Diver",
               "A deep-sea suit with a round viewing dome.",
               .uncommon, "auroradiver", .coins(150),
               dyes: [c(0.10, 0.36, 0.48), c(0.18, 0.78, 0.72), c(0.96, 0.72, 0.22)]),
            it("costume.harvestpilot", "Harvest Pilot",
               "A leather cap, goggles and a wind-ready jacket.",
               .uncommon, "harvestpilot", .coins(130),
               dyes: [c(0.42, 0.28, 0.18), c(0.72, 0.18, 0.16), c(0.18, 0.32, 0.22)]),
            it("costume.candymage", "Candy Alchemist",
               "A sweet-striped robe for kitchen spells.",
               .common, "candymage", .coins(90),
               dyes: [c(0.96, 0.46, 0.62), c(0.46, 0.82, 0.86), c(0.98, 0.86, 0.40)]),
            it("costume.meadowbard", "Meadow Bard",
               "A leafy tunic, a soft cap and a travel lute.",
               .common, "meadowbard", .coins(90),
               dyes: [c(0.36, 0.55, 0.28), c(0.72, 0.42, 0.22), c(0.92, 0.78, 0.36)]),
        ]
    }
}

extension MascotOutfit {
    /// Slots a worn costume temporarily replaces. Background, pets, auras and held items stay put.
    static var costumeCoveredSlots: [MascotWardrobeSlot] { MascotCostumeCatalog.coveredSlots }

    var costume: MascotWardrobeItem? { item(for: .costume) }
    var hasCostume: Bool { items[MascotWardrobeSlot.costume.rawValue] != nil }

    /// Parks covered slot items, then equips the costume, so taking it off can restore them.
    mutating func equipCostume(_ item: MascotWardrobeItem, dye: Int? = nil) {
        precondition(item.slot == .costume)
        parkCoveredSlotsIfNeeded()
        items[MascotWardrobeSlot.costume.rawValue] = item.id
        if let dye {
            dyes[MascotWardrobeSlot.costume.rawValue] = dye
        } else if dyes[MascotWardrobeSlot.costume.rawValue] == nil {
            dyes[MascotWardrobeSlot.costume.rawValue] = 0
        }
    }

    /// Removes the costume and puts parked slot items back. Nothing is discarded.
    @discardableResult
    mutating func unequipCostume() -> Bool {
        guard items.removeValue(forKey: MascotWardrobeSlot.costume.rawValue) != nil else { return false }
        dyes.removeValue(forKey: MascotWardrobeSlot.costume.rawValue)
        restoreParkedSlots()
        return true
    }

    mutating func parkCoveredSlotsIfNeeded() {
        for slot in Self.costumeCoveredSlots {
            let key = slot.rawValue
            if let id = items.removeValue(forKey: key) {
                if parkedItems[key] == nil { parkedItems[key] = id }
            }
            if let dye = dyes.removeValue(forKey: key) {
                if parkedDyes[key] == nil { parkedDyes[key] = dye }
            }
        }
    }

    mutating func restoreParkedSlots() {
        for (key, id) in parkedItems where items[key] == nil {
            items[key] = id
        }
        for (key, dye) in parkedDyes where dyes[key] == nil {
            dyes[key] = dye
        }
        parkedItems = [:]
        parkedDyes = [:]
    }
}

/// Compact rarity + price label used on wardrobe tiles. Labels only — no payments.
struct MolibooWardrobePriceLabel: View {
    let item: MascotWardrobeItem
    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(item.rarity.color).frame(width: 5, height: 5)
            Text(item.rarity.title)
            Text("·")
            if let price = item.coinPrice {
                Text("\(price)")
            } else if item.isPremium {
                Text("Premium")
            } else {
                Text("Free")
            }
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}
