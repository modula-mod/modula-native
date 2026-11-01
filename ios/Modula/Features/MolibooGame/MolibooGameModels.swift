import Foundation

// MARK: - Rig interface

/// The one contract between game systems and the Moliboo rig (owned by the art/rig stream).
/// A full outfit is an ordered list of wearable slot items; the rig renders `slots` in
/// `MolibooWearableSlot.drawOrder` and ignores slots it cannot fit yet (no clipping hacks here).
struct MolibooOutfitSet: Codable, Hashable, Sendable {
    struct SlotItem: Codable, Hashable, Sendable {
        let slot: MolibooWearableSlot
        let itemId: String?
    }
    let characterId: String
    let slots: [SlotItem]

    var itemIds: [String] { slots.compactMap(\.itemId) }
    func item(for slot: MolibooWearableSlot) -> String? { slots.first { $0.slot == slot }?.itemId }
}

enum MolibooWearableSlot: String, Codable, CaseIterable, Hashable, Sendable, Identifiable {
    case headwear, hair, face, top, outerwear, bottom, footwear, back, handheld, aura
    var id: String { rawValue }
    /// Back-to-front draw order suggestion for the rig (aura behind, back items behind body).
    static let drawOrder: [MolibooWearableSlot] = [.aura, .back, .bottom, .footwear, .top, .outerwear, .hair, .face, .headwear, .handheld]
    var title: String {
        switch self {
        case .headwear: "Hats"
        case .hair: "Hair"
        case .face: "Face"
        case .top: "Tops"
        case .outerwear: "Outerwear"
        case .bottom: "Bottoms"
        case .footwear: "Shoes"
        case .back: "Back"
        case .handheld: "Props"
        case .aura: "Auras"
        }
    }
    var symbol: String {
        switch self {
        case .headwear: "crown.fill"
        case .hair: "comb.fill"
        case .face: "eyeglasses"
        case .top: "tshirt.fill"
        case .outerwear: "jacket.fill"
        case .bottom: "figure.stand"
        case .footwear: "shoe.fill"
        case .back: "backpack.fill"
        case .handheld: "wand.and.stars"
        case .aura: "sparkles"
        }
    }
}

// MARK: - Server DTOs (GreenField /v1/moliboo/*). Ownership is never computed on device.

struct MolibooGameItem: Codable, Hashable, Sendable, Identifiable {
    let itemId: String
    let name: String
    let slot: MolibooWearableSlot
    let rarity: String
    let access: String
    let family: String?
    let setId: String?
    let iconKey: String
    var id: String { itemId }
}

struct MolibooInventoryEntry: Codable, Hashable, Sendable, Identifiable {
    let item: MolibooGameItem
    /// owned | free | earnable_locked | premium_locked
    let status: String
    let source: String?
    let acquiredAt: String?
    let unlockQuestId: String?
    var id: String { item.itemId }
    var usable: Bool { status == "owned" || status == "free" }
}

struct MolibooInventory: Codable, Sendable {
    struct Counts: Codable, Sendable { let owned: Int; let free: Int; let locked: Int }
    let counts: Counts
    let entries: [MolibooInventoryEntry]
}

struct MolibooCuratedOutfit: Codable, Hashable, Sendable, Identifiable {
    struct SetItem: Codable, Hashable, Sendable {
        let itemId: String
        let name: String
        let slot: MolibooWearableSlot
        let iconKey: String
        let usable: Bool
    }
    struct Completion: Codable, Hashable, Sendable { let owned: Int; let total: Int; let complete: Bool }
    struct SetBonus: Codable, Hashable, Sendable { let buffId: String; let name: String; let description: String }
    let setId: String
    let name: String
    let family: String?
    let access: String
    let rarity: String
    let iconKey: String
    let items: [SetItem]
    let completion: Completion?
    let setBonus: SetBonus?
    var id: String { setId }
}

struct MolibooSavedOutfit: Codable, Hashable, Sendable, Identifiable {
    let outfitId: String
    let name: String
    let characterId: String?
    let itemIds: [String]
    let revision: Int
    var id: String { outfitId }
}

struct MolibooSkill: Codable, Hashable, Sendable {
    let skillId: String
    let name: String
    let description: String
    let cooldownSeconds: Int
    let availableAt: String?
    let ready: Bool
}

struct MolibooBuff: Codable, Hashable, Sendable, Identifiable {
    let buffId: String
    let name: String?
    let description: String?
    let stacks: Int
    let maxStacks: Int
    let source: String
    let expiresAt: String?
    var id: String { buffId }
    var expiresDate: Date? { expiresAt.flatMap(MolibooGameDates.parse) }
}

struct MolibooFriendship: Codable, Hashable, Sendable {
    let xp: Int
    let level: Int
    let xpIntoLevel: Int
    let xpForNext: Int
    let bonusPct: Int
}

struct MolibooCharacterState: Codable, Sendable {
    struct Equipped: Codable, Sendable { let itemIds: [String]; let sourceSetId: String?; let revision: Int }
    struct SetBonus: Codable, Sendable { let setId: String; let name: String }
    let characterId: String
    let equipped: Equipped
    let outfitSet: MolibooOutfitSet
    let setBonus: SetBonus?
    let skill: MolibooSkill?
    let buffs: [MolibooBuff]
    let friendship: MolibooFriendship
}

struct MolibooQuest: Codable, Hashable, Sendable, Identifiable {
    struct Reward: Codable, Hashable, Sendable {
        let type: String
        let amount: Int?
        let itemId: String?
        let item: MolibooGameItem?
        let poolItems: [MolibooGameItem]?
    }
    let questId: String
    let kind: String
    let title: String
    let description: String
    let target: Int
    let progress: Int
    let completed: Bool
    let claimed: Bool
    let resetsAt: String?
    let reward: Reward
    var id: String { questId }
    var fraction: Double { target == 0 ? 0 : min(1, Double(progress) / Double(target)) }
}

struct MolibooQuestBoard: Codable, Sendable { let quests: [MolibooQuest] }

enum MolibooGameCareAction: String, CaseIterable, Identifiable, Sendable {
    case feed, play, rest, groom, talk
    var id: String { rawValue }
    var title: String {
        switch self {
        case .feed: "Snack"
        case .play: "Play"
        case .rest: "Nap"
        case .groom: "Groom"
        case .talk: "Chat"
        }
    }
    var symbol: String {
        switch self {
        case .feed: "fork.knife"
        case .play: "figure.play"
        case .rest: "moon.zzz.fill"
        case .groom: "comb.fill"
        case .talk: "bubble.left.and.bubble.right.fill"
        }
    }
}

enum MolibooGameActivity: String, CaseIterable, Identifiable, Sendable {
    case bubblePop = "bubble_pop", starCatch = "star_catch", memoryMatch = "memory_match"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bubblePop: "Bubble Pop"
        case .starCatch: "Star Catch"
        case .memoryMatch: "Memory Match"
        }
    }
}

enum MolibooGameDates {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()
    static func parse(_ s: String) -> Date? { fractional.date(from: s) ?? plain.date(from: s) }
}

/// Maps a native character id ("pip", "moliboo.027") to the GreenField game id `moliboo.<family>.<name>`.
enum MolibooGameCharacterID {
    static func server(for nativeID: String) -> String {
        if let entry = MolibooRegistryStore.bundled?.character(id: nativeID) ?? MolibooRegistryStore.bundled?.character(key: nativeID) {
            return "moliboo.\(slug(entry.familyId)).\(slug(entry.name))"
        }
        return "moliboo.originals.\(slug(nativeID))"
    }
    static func slug(_ s: String) -> String {
        let lowered = s.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" }
        return String(lowered).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}
