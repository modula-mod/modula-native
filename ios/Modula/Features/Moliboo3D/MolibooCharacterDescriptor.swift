import Foundation

enum MolibooExpression: String, CaseIterable, Codable, Sendable {
    case idle, blink, happy, excited, surprised, sleepy, sad
    var title: String {
        switch self {
        case .idle: "Idle"
        case .blink: "Blink"
        case .happy: "Happy"
        case .excited: "Excited"
        case .surprised: "Surprised"
        case .sleepy: "Sleepy"
        case .sad: "Sad"
        }
    }
    /// Baked hold clip on the USD timeline (blend-shape pose). Blink is a one-shot clip.
    var clipName: String { self == .blink ? "blink" : "expr_\(rawValue)" }
}

/// Frame range of an animation clip baked onto the single USD timeline.
struct MolibooClip: Codable, Equatable, Sendable {
    let start: Int
    let end: Int
}

/// A 3D cosmetic: separate geometry (its own USDZ) linked to a stable wardrobe item ID.
struct MolibooCosmeticDescriptor: Codable, Equatable, Sendable {
    let wardrobeItemID: String
    let asset: String
    let assetSHA256: String
    /// Frozen source tag (e.g. "pebble-v2.2-frozen"); nil for unreleased assets.
    let sourceVersion: String?
}

/// Per-character attachment of one cosmetic. Offsets/rotations are in the character's authoring frame
/// (Blender Z-up, metres, Euler XYZ degrees) relative to `anchor`.
struct MolibooAttachmentConfig: Codable, Equatable, Sendable {
    let anchor: String
    let offset: [Float]
    let rotationDegrees: [Float]
    let scale: Float
    let compatible: Bool
}

enum MolibooCompatibility: Equatable, Sendable {
    case compatible(MolibooAttachmentConfig)
    case notCompatible
    var isCompatible: Bool { if case .compatible = self { return true }; return false }
}

struct MolibooCharacterDescriptor: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let canonicalNumber: Int
    let displayName: String
    let family: String
    /// nil = character has no 3D model yet (2D only).
    let asset: String?
    let assetSHA256: String?
    /// Frozen source tag of the 3D model; nil when the character has no 3D model.
    let sourceVersion: String?
    let anchors: [String]
    let expressions: [MolibooExpression]
    let fps: Int
    let clips: [String: MolibooClip]
    /// wardrobe item ID → attachment. Missing entry = not compatible (never guessed).
    let attachments: [String: MolibooAttachmentConfig]

    var has3DModel: Bool { asset != nil }

    func compatibility(forWardrobeItem id: String) -> MolibooCompatibility {
        guard has3DModel, let c = attachments[id], c.compatible, anchors.contains(c.anchor) else { return .notCompatible }
        return .compatible(c)
    }
}

struct MolibooManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let cosmetics: [MolibooCosmeticDescriptor]
    let characters: [MolibooCharacterDescriptor]

    func character(id: String) -> MolibooCharacterDescriptor? { characters.first { $0.id == id } }
    func cosmetic(forWardrobeItem id: String) -> MolibooCosmeticDescriptor? { cosmetics.first { $0.wardrobeItemID == id } }

    /// Single entry point for "can character X wear item Y in 3D?".
    func compatibility(item: String, character: String) -> MolibooCompatibility {
        guard cosmetic(forWardrobeItem: item) != nil, let c = self.character(id: character) else { return .notCompatible }
        return c.compatibility(forWardrobeItem: item)
    }

    enum LoadError: Error { case missing, unsupportedSchema(Int) }

    static func decode(_ data: Data) throws -> MolibooManifest {
        let m = try JSONDecoder().decode(MolibooManifest.self, from: data)
        guard m.schemaVersion == 2 else { throw LoadError.unsupportedSchema(m.schemaVersion) }
        return m
    }

    static func bundled(_ bundle: Bundle = .main) throws -> MolibooManifest {
        guard let url = bundle.url(forResource: "moliboo_manifest", withExtension: "json") else { throw LoadError.missing }
        return try decode(Data(contentsOf: url))
    }
}
