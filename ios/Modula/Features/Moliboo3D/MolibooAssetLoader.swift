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
