import SwiftUI

// MARK: - Achievements

struct MascotAchievement: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let rewardItemID: String?
    let rewardCoins: Int

    static let all: [MascotAchievement] = [
        MascotAchievement(id: "first_comment", title: "First words", detail: "Post your first comment.", symbol: "text.bubble.fill", rewardItemID: "acc.firstpin", rewardCoins: 50),
        MascotAchievement(id: "streak_7", title: "On a roll", detail: "Open Modula 7 days in a row.", symbol: "flame.fill", rewardItemID: "back.streakcape", rewardCoins: 150),
        MascotAchievement(id: "reactions_10", title: "Big heart", detail: "React to 10 posts or comments.", symbol: "heart.fill", rewardItemID: "aura.heartburst", rewardCoins: 100),
        MascotAchievement(id: "birthday", title: "Birthday buddy", detail: "Visit your Moliboo on your birthday.", symbol: "gift.fill", rewardItemID: "hat.bdaycrown", rewardCoins: 200),
        MascotAchievement(id: "stylist", title: "Stylist", detail: "Save your first outfit preset.", symbol: "hanger", rewardItemID: nil, rewardCoins: 40),
    ]
    static func with(id: String) -> MascotAchievement? { all.first { $0.id == id } }
}

enum MascotProgressEvent: Sendable {
    case comment, reaction, birthday, savedOutfit
}

// MARK: - State (Codable so it can be synced to the server later)

struct MascotProgressState: Codable, Equatable, Sendable {
    var coins: Int = 100
    var owned: Set<String> = []
    var achievements: Set<String> = []
    var streak: Int = 0
    var lastActiveDay: String? = nil
    var comments: Int = 0
    var reactions: Int = 0
    var lastChestDay: String? = nil
    var version: Int = 1

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        coins = try c.decodeIfPresent(Int.self, forKey: .coins) ?? 100
        owned = try c.decodeIfPresent(Set<String>.self, forKey: .owned) ?? []
        achievements = try c.decodeIfPresent(Set<String>.self, forKey: .achievements) ?? []
        streak = try c.decodeIfPresent(Int.self, forKey: .streak) ?? 0
        lastActiveDay = try c.decodeIfPresent(String.self, forKey: .lastActiveDay)
        comments = try c.decodeIfPresent(Int.self, forKey: .comments) ?? 0
        reactions = try c.decodeIfPresent(Int.self, forKey: .reactions) ?? 0
        lastChestDay = try c.decodeIfPresent(String.self, forKey: .lastChestDay)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }
}

struct MascotChestReward: Identifiable, Equatable, Sendable {
    let id = UUID()
    let coins: Int
    let itemID: String?
}

// MARK: - Store

@MainActor @Observable
final class MascotProgressStore {
    static let shared = MascotProgressStore()
    private let key = "composer.mascot.progress"

    private(set) var state: MascotProgressState
    /// Latest unlock to celebrate in the UI (cleared by the view).
    var lastUnlocked: MascotAchievement?

    var coins: Int { state.coins }
    var owned: Set<String> { state.owned }
    var streak: Int { state.streak }

    private init() {
        state = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(MascotProgressState.self, from: $0) } ?? MascotProgressState()
    }

    static func dayKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func isUnlocked(_ a: MascotAchievement) -> Bool { state.achievements.contains(a.id) }

    func progress(for a: MascotAchievement) -> (value: Int, goal: Int) {
        switch a.id {
        case "first_comment": (min(state.comments, 1), 1)
        case "streak_7": (min(state.streak, 7), 7)
        case "reactions_10": (min(state.reactions, 10), 10)
        case "birthday": (isUnlocked(a) ? 1 : 0, 1)
        case "stylist": (isUnlocked(a) ? 1 : 0, 1)
        default: (0, 1)
        }
    }

    /// Call when the app/mascot is opened; advances the daily streak.
    func touchDay() {
        let today = Self.dayKey()
        guard state.lastActiveDay != today else { return }
        let yesterday = Self.dayKey(Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        state.streak = state.lastActiveDay == yesterday ? state.streak + 1 : 1
        state.lastActiveDay = today
        if state.streak >= 7 { unlock("streak_7") }
        save()
    }

    func record(_ event: MascotProgressEvent) {
        switch event {
        case .comment:
            state.comments += 1
            state.coins += 5
            unlock("first_comment")
        case .reaction:
            state.reactions += 1
            state.coins += 1
            if state.reactions >= 10 { unlock("reactions_10") }
        case .birthday:
            unlock("birthday")
        case .savedOutfit:
            unlock("stylist")
        }
        save()
    }

    var canOpenChest: Bool { state.lastChestDay != Self.dayKey() }

    /// Daily reward chest: coins, and sometimes a free-to-earn item you don't own yet.
    func openChest() -> MascotChestReward? {
        guard canOpenChest else { return nil }
        state.lastChestDay = Self.dayKey()
        var coins = Int.random(in: 15...40) + min(state.streak, 7) * 5
        var itemID: String?
        if Int.random(in: 0..<4) == 0,
           let pick = MascotWardrobeCatalog.all.filter({ $0.coinPrice != nil && !state.owned.contains($0.id) }).randomElement() {
            state.owned.insert(pick.id)
            itemID = pick.id
        } else {
            coins += 10
        }
        state.coins += coins
        save()
        return MascotChestReward(coins: coins, itemID: itemID)
    }

    enum BuyResult { case bought, owned, insufficient, notForSale }

    /// Coin shop stub. No real payments; premium items stay behind the entitlement flag.
    @discardableResult
    func buy(_ item: MascotWardrobeItem) -> BuyResult {
        guard let price = item.coinPrice else { return .notForSale }
        if state.owned.contains(item.id) { return .owned }
        guard state.coins >= price else { return .insufficient }
        state.coins -= price
        state.owned.insert(item.id)
        save()
        return .bought
    }

    // Collection

    func ownedCount(in slot: MascotWardrobeSlot) -> Int {
        let store = MascotWardrobeStore.shared
        return MascotWardrobeCatalog.items(in: slot).filter { store.owns($0) }.count
    }
    func collectionFraction(_ slot: MascotWardrobeSlot) -> Double {
        let total = MascotWardrobeCatalog.items(in: slot).count
        return total == 0 ? 0 : Double(ownedCount(in: slot)) / Double(total)
    }

    #if DEBUG
    func debugAddCoins(_ n: Int) { state.coins += n; save() }
    func debugReset() { state = MascotProgressState(); save() }
    #endif

    private func unlock(_ id: String) {
        guard !state.achievements.contains(id), let a = MascotAchievement.with(id: id) else { return }
        state.achievements.insert(id)
        state.coins += a.rewardCoins
        if let item = a.rewardItemID { state.owned.insert(item) }
        lastUnlocked = a
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: key) }
    }
}
