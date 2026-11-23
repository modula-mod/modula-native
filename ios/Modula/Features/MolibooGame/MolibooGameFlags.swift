import Foundation

/// MOLIBOO-GAME-SYSTEMS-01: Inventory, Outfits, skills, buffs and quests talk to
/// `/v1/moliboo/*` GreenField routes (modula-latest PR feature/moliboo-game-systems).
/// Off by default until that backend is deployed; Settings → Labs / debug can flip it.
enum MolibooGameFlags {
    static let enabledKey = "dev.moliboo.gameSystems"
    static var enabled: Bool {
        get {
            if ProcessInfo.processInfo.arguments.contains("-MolibooGameSystems") { return true }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
}
