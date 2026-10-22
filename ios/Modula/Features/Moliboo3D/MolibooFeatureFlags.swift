import Foundation

/// MOL-01 native 3D Moliboos: retired. The 2D renderer is the only path.
enum MolibooFeatureFlags {
    static let native3DKey = "dev.moliboo.native3D"
    /// Moliboos are 2D-only: 3D is forced off (no user or dev toggle). The 3D sources and assets stay dormant.
    static let native3DDefault = false
    static var native3DEnabled: Bool {
        get { false }
        set { UserDefaults.standard.set(false, forKey: native3DKey) }
    }
}
