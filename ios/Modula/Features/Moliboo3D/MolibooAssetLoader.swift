import Foundation
import RealityKit

/// Loads bundled USDZ character/accessory assets. Failure is non-fatal: callers fall back to the 2D renderer.
@MainActor
enum MolibooAssetLoader {
    enum LoadError: Error { case assetMissing(String) }

    static func url(for asset: String, bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: asset, withExtension: "usdz")
    }

    static func loadEntity(_ asset: String, bundle: Bundle = .main) async throws -> Entity {
        guard let url = url(for: asset, bundle: bundle) else { throw LoadError.assetMissing(asset) }
        return try await Entity(contentsOf: url)
    }
}

/// MOL-02: which characters can open in 3D. Generic, manifest-driven: a character qualifies only if the manifest
/// gives it an asset AND that USDZ is actually bundled. Everything else uses the 2D renderer (no Pebble fallback).
@MainActor
enum MolibooRegistry {
    static let manifest: MolibooManifest? = try? MolibooManifest.bundled()

    static func descriptor(for id: String, manifest: MolibooManifest? = manifest, bundle: Bundle = .main) -> MolibooCharacterDescriptor? {
        guard let d = manifest?.character(id: id), let asset = d.asset, MolibooAssetLoader.url(for: asset, bundle: bundle) != nil else { return nil }
        return d
    }
    static func has3D(_ id: String) -> Bool { descriptor(for: id) != nil }
    static var available3D: [MolibooCharacterDescriptor] { (manifest?.characters ?? []).filter { has3D($0.id) } }
}
