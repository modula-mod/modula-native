import Foundation

/// Stable IDs for Moliboo first-party cosmetics. Never reuse or reinterpret existing wardrobe IDs (e.g. `hat.party`).
enum MolibooCosmetics {
    /// "Moliboo Signature Cap" — Common, free to all users (`MascotUnlock.free` ⇒ always owned client-side).
    static let signatureCapID = "cap.moliboo.signature"

    /// The 25 Originals, in canonical order. Characters without an attachment config are "not compatible".
    static let originals: [String] = [
        "pip", "moss", "nimbus", "mochi", "sprout", "ember", "tuck", "bloop", "bun", "pebble",
        "tofu", "comet", "puff", "bolt", "glim", "echo", "quill", "orbit", "prism", "wisp",
        "doodle", "chime", "rolo", "pogo", "fable",
    ]
}
