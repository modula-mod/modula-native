import SwiftUI
import UIKit

// MARK: - Trading cards v2: one collectible card for every registered Moliboo (#001–#215)

/// Design rarity for the card print. This is not ownership and is never presented as a purchase.
enum MolibooGalleryRarity: String, CaseIterable, Comparable, Sendable {
    case common, uncommon, rare, epic, legendary
    private var rank: Int { Self.allCases.firstIndex(of: self)! }
    static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
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
    var foil: Double {
        switch self {
        case .common: 0.05
        case .uncommon: 0.09
        case .rare: 0.14
        case .epic: 0.20
        case .legendary: 0.26
        }
    }
}

struct MolibooFamilyTheme: Equatable, Sendable {
    var accent: Color
    var secondary: Color
    var ink: Color
    var paper: Color
    var foil: [Color]
}

struct MolibooGalleryCard: Identifiable, Equatable, Sendable {
    var id: String { character.id }
    var character: MolibooRegistryCharacter
    var family: MolibooRegistryFamily?
    var rarity: MolibooGalleryRarity
    var theme: MolibooFamilyTheme

    var number: Int { character.number }
    var catalogueNumber: String { character.catalogueNumber }
    var name: String { character.name }
    var familyName: String { family?.name ?? character.familyId }
    var familyId: String { character.familyId }
    var title: String { character.title }
    var flavour: String { character.personality.description }
    var kind: ModulaMascotKind? { character.kind ?? ModulaMascotKind(rawValue: character.key) }
    var isLegend: Bool { familyId == "legends" || character.wearable == false }
    var isSeries2: Bool { number >= 116 }
}

enum MolibooCardGallery {
    static let total = 215

    /// Every registered Moliboo, #001–#215, in number order. Requires the bundled registry.
    static func all(registry: MolibooCharacterRegistry? = MolibooRegistryStore.bundled) -> [MolibooGalleryCard] {
        guard let registry else { return [] }
        return registry.characters.sorted { $0.number < $1.number }.compactMap { character in
            card(character: character, registry: registry)
        }
    }

    static func card(number: Int, registry: MolibooCharacterRegistry? = MolibooRegistryStore.bundled) -> MolibooGalleryCard? {
        guard let registry, let character = registry.character(number: number) else { return nil }
        return card(character: character, registry: registry)
    }

    static func card(id: String, registry: MolibooCharacterRegistry? = MolibooRegistryStore.bundled) -> MolibooGalleryCard? {
        guard let registry, let character = registry.character(id: id) else { return nil }
        return card(character: character, registry: registry)
    }

    static func card(character: MolibooRegistryCharacter, registry: MolibooCharacterRegistry) -> MolibooGalleryCard {
        let family = registry.family(id: character.familyId)
        return MolibooGalleryCard(
            character: character,
            family: family,
            rarity: rarity(for: character, family: family),
            theme: theme(for: family, character: character)
        )
    }

    /// Print treatment by family / series — a design trait, not a claim of ownership.
    static func rarity(for character: MolibooRegistryCharacter, family: MolibooRegistryFamily?) -> MolibooGalleryRarity {
        if character.familyId == "legends" || character.wearable == false { return .legendary }
        if let family, family.series == 2 { return .rare }
        switch character.familyId {
        case "originals": return character.number == 1 ? .epic : .uncommon
        case "angels", "enchanted", "stardust": return .rare
        case "underground", "dreamers": return .uncommon
        default: return .common
        }
    }

    static func theme(for family: MolibooRegistryFamily?, character: MolibooRegistryCharacter) -> MolibooFamilyTheme {
        if let hex = family?.accentHex, let accent = Color(molibooHex: hex) {
            return MolibooFamilyTheme(
                accent: accent,
                secondary: accent.mix(with: .white, by: 0.35),
                ink: accent.mix(with: Color(red: 0.10, green: 0.08, blue: 0.16), by: 0.62),
                paper: Color(red: 0.97, green: 0.96, blue: 0.93),
                foil: [accent, accent.mix(with: .white, by: 0.4), accent.mix(with: .black, by: 0.2), accent]
            )
        }
        return stockTheme(familyId: character.familyId)
    }

    static func stockTheme(familyId: String) -> MolibooFamilyTheme {
        func theme(_ a: Color, _ b: Color, paper: Color = Color(red: 0.97, green: 0.96, blue: 0.93)) -> MolibooFamilyTheme {
            MolibooFamilyTheme(accent: a, secondary: b, ink: a.mix(with: Color(red: 0.10, green: 0.08, blue: 0.16), by: 0.6), paper: paper, foil: [a, b, a.mix(with: .white, by: 0.4), a])
        }
        switch familyId {
        case "originals": return theme(Color(red: 0.21, green: 0.61, blue: 0.67), Color(red: 0.98, green: 0.62, blue: 0.38))
        case "angels": return theme(Color(red: 0.98, green: 0.82, blue: 0.40), Color(red: 0.96, green: 0.94, blue: 0.88))
        case "underground": return theme(Color(red: 0.46, green: 0.30, blue: 0.72), Color(red: 0.22, green: 0.16, blue: 0.28))
        case "enchanted": return theme(Color(red: 0.28, green: 0.62, blue: 0.38), Color(red: 0.86, green: 0.72, blue: 0.30))
        case "stardust": return theme(Color(red: 0.32, green: 0.28, blue: 0.72), Color(red: 0.78, green: 0.82, blue: 0.98))
        case "dreamers": return theme(Color(red: 0.70, green: 0.56, blue: 0.92), Color(red: 0.98, green: 0.82, blue: 0.90))
        case "legends": return theme(Color(red: 0.92, green: 0.70, blue: 0.22), Color(red: 0.55, green: 0.22, blue: 0.16), paper: Color(red: 0.16, green: 0.12, blue: 0.10))
        default: return theme(Color(red: 0.40, green: 0.52, blue: 0.70), Color(red: 0.86, green: 0.80, blue: 0.70))
        }
    }
}

// MARK: - Package portraits (Series 2)

enum MolibooPackagePortrait {
    /// Loads `portrait.png` from an installed character pack, or nil when the pack is not on the device.
    static func image(for character: MolibooRegistryCharacter) -> UIImage? {
        let resolved = resolve(character)
        guard let data = MolibooPackageRuntime.shared.store.activeMedia(packageId: resolved.packageId, path: resolved.path) else {
            return nil
        }
        return UIImage(data: data)
    }

    static func isInstalled(_ character: MolibooRegistryCharacter) -> Bool {
        image(for: character) != nil
    }

    /// Supports `package:<packageId>/<path>` thumbnails from the registry, with a portrait.png fallback.
    static func resolve(_ character: MolibooRegistryCharacter) -> (packageId: String, path: String) {
        if let thumb = character.thumbnail, thumb.hasPrefix("package:") {
            let rest = String(thumb.dropFirst("package:".count))
            if let slash = rest.firstIndex(of: "/") {
                return (String(rest[..<slash]), String(rest[rest.index(after: slash)...]))
            }
        }
        return (character.packageId, "portrait.png")
    }
}
