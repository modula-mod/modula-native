import Foundation

/// MOL-01: native 3D Moliboos are dev-only. Default ON in DEBUG builds (so Studio shows 3D Pebble),
/// default OFF in Release; an explicit UserDefaults value always wins. The 2D renderer stays the rollback path.
enum MolibooFeatureFlags {
    static let native3DKey = "dev.moliboo.native3D"
    #if DEBUG
    static let native3DDefault = true
    #else
    static let native3DDefault = false
    #endif
    static var native3DEnabled: Bool {
        get { (UserDefaults.standard.object(forKey: native3DKey) as? Bool) ?? native3DDefault }
        set { UserDefaults.standard.set(newValue, forKey: native3DKey) }
    }
}
