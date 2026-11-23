import SwiftUI

/// Sprout sticker pack. Series 1 has 36 stickers and series 2 has 29.
/// `02_18_space_explorer` was cut off and is not in the pack.
/// Thumbs are bundled. Greenfield's `GET /v1/stickers/packs` returns its own packs
/// and has no image route for these, so the full 768px files are not downloaded.
struct SproutSticker: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var series: Int
    var assetName: String

    var local: ModulaLocalSticker { ModulaLocalSticker(kind: .sprout, value: id) }
}

enum SproutStickerPack {
    static func sticker(id: String) -> SproutSticker? { byID[id] }

    static var series1Count: Int { all.filter { $0.series == 1 }.count }
    static var series2Count: Int { all.filter { $0.series == 2 }.count }

    static let all: [SproutSticker] = [
        SproutSticker(id: "01_01_crypto", title: "Crypto", series: 1, assetName: "SproutSticker01_01_crypto"),
        SproutSticker(id: "01_02_forex", title: "Forex", series: 1, assetName: "SproutSticker01_02_forex"),
        SproutSticker(id: "01_03_chemistry", title: "Chemistry", series: 1, assetName: "SproutSticker01_03_chemistry"),
        SproutSticker(id: "01_04_builder", title: "Builder", series: 1, assetName: "SproutSticker01_04_builder"),
        SproutSticker(id: "01_05_developer", title: "Developer", series: 1, assetName: "SproutSticker01_05_developer"),
        SproutSticker(id: "01_06_artist", title: "Artist", series: 1, assetName: "SproutSticker01_06_artist"),
        SproutSticker(id: "01_07_music_producer", title: "Music Producer", series: 1, assetName: "SproutSticker01_07_music_producer"),
        SproutSticker(id: "01_08_reader", title: "Reader", series: 1, assetName: "SproutSticker01_08_reader"),
        SproutSticker(id: "01_09_astronaut", title: "Astronaut", series: 1, assetName: "SproutSticker01_09_astronaut"),
        SproutSticker(id: "01_10_gardener", title: "Gardener", series: 1, assetName: "SproutSticker01_10_gardener"),
        SproutSticker(id: "01_11_photographer", title: "Photographer", series: 1, assetName: "SproutSticker01_11_photographer"),
        SproutSticker(id: "01_12_explorer", title: "Explorer", series: 1, assetName: "SproutSticker01_12_explorer"),
        SproutSticker(id: "01_13_gamer", title: "Gamer", series: 1, assetName: "SproutSticker01_13_gamer"),
        SproutSticker(id: "01_14_planner", title: "Planner", series: 1, assetName: "SproutSticker01_14_planner"),
        SproutSticker(id: "01_15_fitness", title: "Fitness", series: 1, assetName: "SproutSticker01_15_fitness"),
        SproutSticker(id: "01_16_chef", title: "Chef", series: 1, assetName: "SproutSticker01_16_chef"),
        SproutSticker(id: "01_17_business", title: "Business", series: 1, assetName: "SproutSticker01_17_business"),
        SproutSticker(id: "01_18_biology", title: "Biology", series: 1, assetName: "SproutSticker01_18_biology"),
        SproutSticker(id: "01_19_doctor", title: "Doctor", series: 1, assetName: "SproutSticker01_19_doctor"),
        SproutSticker(id: "01_20_ai_researcher", title: "Ai Researcher", series: 1, assetName: "SproutSticker01_20_ai_researcher"),
        SproutSticker(id: "01_21_wizard", title: "Wizard", series: 1, assetName: "SproutSticker01_21_wizard"),
        SproutSticker(id: "01_22_scientist", title: "Scientist", series: 1, assetName: "SproutSticker01_22_scientist"),
        SproutSticker(id: "01_23_product_designer", title: "Product Designer", series: 1, assetName: "SproutSticker01_23_product_designer"),
        SproutSticker(id: "01_24_filmmaker", title: "Filmmaker", series: 1, assetName: "SproutSticker01_24_filmmaker"),
        SproutSticker(id: "01_25_health", title: "Health", series: 1, assetName: "SproutSticker01_25_health"),
        SproutSticker(id: "01_26_law", title: "Law", series: 1, assetName: "SproutSticker01_26_law"),
        SproutSticker(id: "01_27_research", title: "Research", series: 1, assetName: "SproutSticker01_27_research"),
        SproutSticker(id: "01_28_writer", title: "Writer", series: 1, assetName: "SproutSticker01_28_writer"),
        SproutSticker(id: "01_29_meditation", title: "Meditation", series: 1, assetName: "SproutSticker01_29_meditation"),
        SproutSticker(id: "01_30_space_science", title: "Space Science", series: 1, assetName: "SproutSticker01_30_space_science"),
        SproutSticker(id: "01_31_ecology", title: "Ecology", series: 1, assetName: "SproutSticker01_31_ecology"),
        SproutSticker(id: "01_32_cybersecurity", title: "Cybersecurity", series: 1, assetName: "SproutSticker01_32_cybersecurity"),
        SproutSticker(id: "01_33_pet_care", title: "Pet Care", series: 1, assetName: "SproutSticker01_33_pet_care"),
        SproutSticker(id: "01_34_winter", title: "Winter", series: 1, assetName: "SproutSticker01_34_winter"),
        SproutSticker(id: "01_35_holiday", title: "Holiday", series: 1, assetName: "SproutSticker01_35_holiday"),
        SproutSticker(id: "01_36_beach", title: "Beach", series: 1, assetName: "SproutSticker01_36_beach"),
        SproutSticker(id: "02_01_crypto_market", title: "Crypto Market", series: 2, assetName: "SproutSticker02_01_crypto_market"),
        SproutSticker(id: "02_02_global_trading", title: "Global Trading", series: 2, assetName: "SproutSticker02_02_global_trading"),
        SproutSticker(id: "02_03_chemist", title: "Chemist", series: 2, assetName: "SproutSticker02_03_chemist"),
        SproutSticker(id: "02_04_construction", title: "Construction", series: 2, assetName: "SproutSticker02_04_construction"),
        SproutSticker(id: "02_05_software_engineer", title: "Software Engineer", series: 2, assetName: "SproutSticker02_05_software_engineer"),
        SproutSticker(id: "02_06_painter", title: "Painter", series: 2, assetName: "SproutSticker02_06_painter"),
        SproutSticker(id: "02_07_esports", title: "Esports", series: 2, assetName: "SproutSticker02_07_esports"),
        SproutSticker(id: "02_08_musician", title: "Musician", series: 2, assetName: "SproutSticker02_08_musician"),
        SproutSticker(id: "02_09_scholar", title: "Scholar", series: 2, assetName: "SproutSticker02_09_scholar"),
        SproutSticker(id: "02_10_ai_expert", title: "Ai Expert", series: 2, assetName: "SproutSticker02_10_ai_expert"),
        SproutSticker(id: "02_11_educator", title: "Educator", series: 2, assetName: "SproutSticker02_11_educator"),
        SproutSticker(id: "02_12_botanist", title: "Botanist", series: 2, assetName: "SproutSticker02_12_botanist"),
        SproutSticker(id: "02_13_traveler", title: "Traveler", series: 2, assetName: "SproutSticker02_13_traveler"),
        SproutSticker(id: "02_14_cooking", title: "Cooking", series: 2, assetName: "SproutSticker02_14_cooking"),
        SproutSticker(id: "02_15_personal_trainer", title: "Personal Trainer", series: 2, assetName: "SproutSticker02_15_personal_trainer"),
        SproutSticker(id: "02_16_photography", title: "Photography", series: 2, assetName: "SproutSticker02_16_photography"),
        SproutSticker(id: "02_17_entrepreneur", title: "Entrepreneur", series: 2, assetName: "SproutSticker02_17_entrepreneur"),
        SproutSticker(id: "02_19_writing", title: "Writing", series: 2, assetName: "SproutSticker02_19_writing"),
        SproutSticker(id: "02_20_languages", title: "Languages", series: 2, assetName: "SproutSticker02_20_languages"),
        SproutSticker(id: "02_21_security_engineer", title: "Security Engineer", series: 2, assetName: "SproutSticker02_21_security_engineer"),
        SproutSticker(id: "02_22_environmentalist", title: "Environmentalist", series: 2, assetName: "SproutSticker02_22_environmentalist"),
        SproutSticker(id: "02_23_mindfulness", title: "Mindfulness", series: 2, assetName: "SproutSticker02_23_mindfulness"),
        SproutSticker(id: "02_24_animal_care", title: "Animal Care", series: 2, assetName: "SproutSticker02_24_animal_care"),
        SproutSticker(id: "02_25_architect", title: "Architect", series: 2, assetName: "SproutSticker02_25_architect"),
        SproutSticker(id: "02_26_investigator", title: "Investigator", series: 2, assetName: "SproutSticker02_26_investigator"),
        SproutSticker(id: "02_27_film_creator", title: "Film Creator", series: 2, assetName: "SproutSticker02_27_film_creator"),
        SproutSticker(id: "02_28_horticulture", title: "Horticulture", series: 2, assetName: "SproutSticker02_28_horticulture"),
        SproutSticker(id: "02_29_personal_finance", title: "Personal Finance", series: 2, assetName: "SproutSticker02_29_personal_finance"),
        SproutSticker(id: "02_30_librarian", title: "Librarian", series: 2, assetName: "SproutSticker02_30_librarian"),
    ]

    private static let byID: [String: SproutSticker] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
}

struct SproutStickerImage: View {
    var assetName: String
    var size: CGFloat

    var body: some View {
        Image(assetName)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
