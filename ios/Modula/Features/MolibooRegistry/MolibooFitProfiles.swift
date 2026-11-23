import Foundation

// MARK: - MOL-03B per-character accessory fitting profiles (schema modula.moliboo.fits.1)
//
// Coordinates follow the 2D rig: fractions of the figure size `s`, measured from the centre of the figure canvas
// (2.0 s × 1.9 s), x grows right, y grows DOWN, rotation in degrees clockwise. `anchor.y` is where the cap brim rests
// (MascotRig.headTop), `width` is the fitted cap width (MascotRig.hatWidth) and `sink` how far it may settle onto the head
// without touching the eyes. The cap is drawn in the wardrobe `front` layer, inside the figure's transform, so it follows
// every head motion. Profiles are exported from measured renders by MOL03VisualAcceptanceTests (MOLIBOO_FIT_EXPORT) and
// re-checked against the live rig on every test run.

struct MolibooFitPoint: Codable, Equatable, Sendable { var x: Double; var y: Double }

struct MolibooFitMeasured: Codable, Equatable, Sendable {
    /// Worst share (still + animated phases) of cap pixels touching the character's silhouette.
    var attachedFraction: Double
    /// Worst share of the eye zones painted over by the cap.
    var eyeCover: Double
    var phasesChecked: [String]
}

struct MolibooFitProfile: Codable, Equatable, Sendable {
    var characterId: String
    var accessoryId: String
    var anchor: MolibooFitPoint
    var scale: Double
    var width: Double
    var maxWidth: Double?
    var rotation: Double
    var zIndex: Int
    var layer: String
    var occlusion: String
    var followHeadMotion: Bool
    var sink: Double
    var eyeClearance: Double
    var validated: Bool
    var measured: MolibooFitMeasured?
}

struct MolibooFitFile: Codable, Equatable, Sendable {
    static let schemaVersion = "modula.moliboo.fits.1"
    var schemaVersion: String
    var accessoryId: String
    var coordinateConvention: String
    var profiles: [String: MolibooFitProfile]
}

enum MolibooFitProfiles {
    static let resourceName = "moliboo_accessory_fits"
    static let convention = "Fractions of figure size s from the canvas centre (canvas 2.0s x 1.9s); x right, y DOWN; rotation degrees clockwise; zIndex 30 = wardrobe front layer."

    /// Decoded lazily on first use.
    static let bundled: MolibooFitFile? = {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MolibooFitFile.self, from: data)
    }()

    static func encode(_ file: MolibooFitFile) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(file) + Data("\n".utf8)
    }

    /// Profile computed from the live rig for one wearable character.
    static func rigProfile(_ kind: ModulaMascotKind, accessoryId: String = "cap.moliboo.signature") -> MolibooFitProfile {
        let rig = MascotRig.stock(kind)
        func r(_ v: CGFloat) -> Double { (Double(v) * 10_000).rounded() / 10_000 }
        return MolibooFitProfile(
            characterId: kind.registryID, accessoryId: accessoryId,
            anchor: MolibooFitPoint(x: 0, y: r(rig.headTop)), scale: r(rig.hatScale), width: r(rig.hatWidth),
            maxWidth: rig.hatMaxWidth.map(r), rotation: 0, zIndex: 30, layer: "front",
            occlusion: "head-top props hide while a hat is worn; ears, horns and halos stay in their own layers",
            followHeadMotion: true, sink: r(rig.hatSink), eyeClearance: r(rig.eyeTop - rig.headTop),
            validated: false, measured: nil)
    }
}
