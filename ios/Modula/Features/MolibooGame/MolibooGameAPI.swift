import Foundation

/// Thin client for the GreenField Moliboo game routes. Only real, server-backed routes;
/// every response is decoded from the server and nothing is invented locally.
struct MolibooGameAPI: Sendable {
    let client: GreenfieldClient

    enum Path {
        static let items = "/v1/moliboo/catalogue/items"
        static let outfitSets = "/v1/moliboo/catalogue/outfits"
        static let inventory = "/v1/moliboo/inventory"
        static let savedOutfits = "/v1/moliboo/outfits"
        static let quests = "/v1/moliboo/quests"
        static let activities = "/v1/moliboo/activities/complete"
        static func state(_ c: String) -> String { "/v1/moliboo/characters/\(c)/state" }
        static func equip(_ c: String) -> String { "/v1/moliboo/characters/\(c)/equip" }
        static func care(_ c: String) -> String { "/v1/moliboo/characters/\(c)/care" }
        static func skill(_ c: String, _ s: String) -> String { "/v1/moliboo/characters/\(c)/skills/\(s)/use" }
        static func outfit(_ id: String) -> String { "/v1/moliboo/outfits/\(id)" }
        static func claim(_ q: String) -> String { "/v1/moliboo/quests/\(q)/claim" }
    }

    private struct SetsEnvelope: Decodable { let sets: [MolibooCuratedOutfit] }
    private struct SavedEnvelope: Decodable { let outfits: [MolibooSavedOutfit] }
    private struct SavedOne: Decodable { let outfit: MolibooSavedOutfit }
    private struct StateEnvelope: Decodable { let state: MolibooCharacterState }

    private func decode<T: Decodable>(_ value: JSONValue, as: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }
    private func key() -> String { "ios-\(UUID().uuidString.lowercased())" }

    func inventory() async throws -> MolibooInventory {
        try decode(await client.authenticatedJSON("GET", path: Path.inventory))
    }
    func outfitSets() async throws -> [MolibooCuratedOutfit] {
        try decode(await client.authenticatedJSON("GET", path: Path.outfitSets), as: SetsEnvelope.self).sets
    }
    func savedOutfits() async throws -> [MolibooSavedOutfit] {
        try decode(await client.authenticatedJSON("GET", path: Path.savedOutfits), as: SavedEnvelope.self).outfits
    }
    func saveOutfit(name: String, characterId: String, itemIds: [String]) async throws -> MolibooSavedOutfit {
        let body: JSONValue = .object(["name": .string(name), "characterId": .string(characterId), "itemIds": .array(itemIds.map(JSONValue.string))])
        return try decode(await client.authenticatedJSON("POST", path: Path.savedOutfits, body: body), as: SavedOne.self).outfit
    }
    func deleteOutfit(_ id: String) async throws {
        _ = try await client.authenticatedJSON("DELETE", path: Path.outfit(id))
    }
    func state(_ characterId: String) async throws -> MolibooCharacterState {
        try decode(await client.authenticatedJSON("GET", path: Path.state(characterId)))
    }
    func equip(_ characterId: String, setId: String? = nil, outfitId: String? = nil, itemIds: [String]? = nil) async throws -> MolibooCharacterState {
        var body: [String: JSONValue] = ["idempotencyKey": .string(key())]
        if let setId { body["setId"] = .string(setId) }
        if let outfitId { body["outfitId"] = .string(outfitId) }
        if let itemIds { body["itemIds"] = .array(itemIds.map(JSONValue.string)) }
        return try decode(await client.authenticatedJSON("POST", path: Path.equip(characterId), body: .object(body)), as: StateEnvelope.self).state
    }
    func care(_ characterId: String, action: MolibooCareAction) async throws -> (counted: Bool, state: MolibooCharacterState) {
        struct R: Decodable { let counted: Bool; let state: MolibooCharacterState }
        let r: R = try decode(await client.authenticatedJSON("POST", path: Path.care(characterId),
                                                            body: .object(["action": .string(action.rawValue), "idempotencyKey": .string(key())])))
        return (r.counted, r.state)
    }
    func useSkill(_ characterId: String, skillId: String) async throws -> MolibooCharacterState {
        try decode(await client.authenticatedJSON("POST", path: Path.skill(characterId, skillId),
                                                  body: .object(["idempotencyKey": .string(key())])), as: StateEnvelope.self).state
    }
    func quests() async throws -> [MolibooQuest] {
        try decode(await client.authenticatedJSON("GET", path: Path.quests), as: MolibooQuestBoard.self).quests
    }
    func claim(_ questId: String, characterId: String) async throws {
        _ = try await client.authenticatedJSON("POST", path: Path.claim(questId), body: .object(["characterId": .string(characterId)]))
    }
    func completeActivity(_ activity: MolibooActivity, characterId: String) async throws {
        _ = try await client.authenticatedJSON("POST", path: Path.activities, body: .object([
            "activityId": .string(activity.rawValue), "characterId": .string(characterId), "idempotencyKey": .string(key()),
        ]))
    }
}

/// Screen state for the game systems of one Moliboo. Server is the source of truth: after every
/// write the returned state replaces local state (no optimistic ownership).
@MainActor @Observable
final class MolibooGameStore {
    let characterId: String
    private let api: MolibooGameAPI

    var inventory: MolibooInventory?
    var sets: [MolibooCuratedOutfit] = []
    var saved: [MolibooSavedOutfit] = []
    var state: MolibooCharacterState?
    var quests: [MolibooQuest] = []
    var busy = false
    var message: String?

    init(nativeCharacterID: String, client: GreenfieldClient) {
        self.characterId = MolibooGameCharacterID.server(for: nativeCharacterID)
        self.api = MolibooGameAPI(client: client)
    }

    func item(_ id: String) -> MolibooGameItem? { inventory?.entries.first { $0.item.itemId == id }?.item }

    func loadAll() async {
        await run(nil) {
            async let inv = self.api.inventory()
            async let sets = self.api.outfitSets()
            async let saved = self.api.savedOutfits()
            async let state = self.api.state(self.characterId)
            async let quests = self.api.quests()
            let (i, s, sv, st, q) = try await (inv, sets, saved, state, quests)
            self.inventory = i; self.sets = s; self.saved = sv; self.state = st; self.quests = q
        }
    }

    func equip(set: MolibooCuratedOutfit) async {
        await run("Wearing \(set.name)") { self.state = try await self.api.equip(self.characterId, setId: set.setId); try await self.refreshSide() }
    }
    func equip(saved outfit: MolibooSavedOutfit) async {
        await run("Wearing \(outfit.name)") { self.state = try await self.api.equip(self.characterId, outfitId: outfit.outfitId); try await self.refreshSide() }
    }
    func saveCurrent(named name: String) async {
        guard let ids = state?.equipped.itemIds, !ids.isEmpty else { message = "Put something on first"; return }
        await run("Saved “\(name)”") {
            _ = try await self.api.saveOutfit(name: name, characterId: self.characterId, itemIds: ids)
            self.saved = try await self.api.savedOutfits(); self.quests = try await self.api.quests()
        }
    }
    func delete(_ outfit: MolibooSavedOutfit) async {
        await run(nil) { try await self.api.deleteOutfit(outfit.outfitId); self.saved = try await self.api.savedOutfits() }
    }
    func care(_ action: MolibooCareAction) async {
        await run(nil) {
            let r = try await self.api.care(self.characterId, action: action)
            self.state = r.state
            self.message = r.counted ? "\(action.title) ✓" : "Already happy. That one counts again in a bit"
            self.quests = try await self.api.quests()
        }
    }
    func useSkill() async {
        guard let skill = state?.skill else { return }
        await run(skill.name) { self.state = try await self.api.useSkill(self.characterId, skillId: skill.skillId); self.quests = try await self.api.quests() }
    }
    func claim(_ quest: MolibooQuest) async {
        await run("Reward collected") {
            try await self.api.claim(quest.questId, characterId: self.characterId)
            async let q = self.api.quests(); async let i = self.api.inventory(); async let s = self.api.state(self.characterId); async let sets = self.api.outfitSets()
            (self.quests, self.inventory, self.state, self.sets) = try await (q, i, s, sets)
        }
    }
    func finish(_ activity: MolibooActivity) async {
        await run("\(activity.title) done") { try await self.api.completeActivity(activity, characterId: self.characterId); self.quests = try await self.api.quests() }
    }

    private func refreshSide() async throws { self.quests = try await api.quests() }

    private func run(_ success: String?, _ work: @escaping @MainActor () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await work()
            if let success { message = success }
        } catch let APIError.rejected(status, code) {
            message = status == 409 ? "Not yet: unlock the missing pieces first" : "Couldn’t do that (\(code))"
        } catch {
            message = "Moliboo games are offline right now"
        }
    }
}
