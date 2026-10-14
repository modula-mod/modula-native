import Foundation
import RealityKit
import UIKit

/// Loads bundled USDZ character/accessory assets. Failure is non-fatal: callers fall back to the 2D renderer.
///
/// Load-once, clone-per-open (MOL-02 stability track): every `Entity(contentsOf:)` makes RealityKit parse the
/// USD and register and compile its materials again. Repeated registration during Studio open/close was where the
/// simulator crashed (Metal reflection objects freed inside `MaterialAssetLoader::registerAsset`). A loaded entity
/// is kept as a template and every caller gets `clone(recursive: true)`, which shares mesh, material and texture
/// resources. The cache is bounded: cosmetics plus the `characterCapacity` most recently used characters.
@MainActor
enum MolibooAssetLoader {
    enum LoadError: Error { case assetMissing(String) }

    static var characterCapacity = 2
    private static var templates: [String: Entity] = [:]
    private static var inFlight: [String: Task<Entity, Error>] = [:]
    private static var recentCharacters: [String] = []   // most recent last
    private(set) static var stats = (hits: 0, misses: 0)

    static func url(for asset: String, bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: asset, withExtension: "usdz")
    }

    private static var memoryObserver: NSObjectProtocol?
    private static func observeMemoryPressure() {
        guard memoryObserver == nil else { return }
        memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                                                object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { templates.removeAll(); recentCharacters.removeAll() }   // live clones keep their own resources
        }
    }

    static func isCached(_ asset: String) -> Bool { templates[asset] != nil }

    /// Returns a fresh clone. Concurrent requests for the same asset share one load.
    static func loadEntity(_ asset: String, bundle: Bundle = .main, isCosmetic: Bool = false) async throws -> Entity {
        observeMemoryPressure()
        if let t = templates[asset] {
            stats.hits += 1; touch(asset, isCosmetic: isCosmetic)
            return t.clone(recursive: true)
        }
        let task: Task<Entity, Error>
        if let running = inFlight[asset] { task = running } else {
            guard let url = url(for: asset, bundle: bundle) else { throw LoadError.assetMissing(asset) }
            stats.misses += 1
            task = Task { @MainActor in try await Entity(contentsOf: url) }
            inFlight[asset] = task
        }
        do {
            let template = try await task.value
            inFlight[asset] = nil
            if templates[asset] == nil { templates[asset] = template }
            touch(asset, isCosmetic: isCosmetic)
            return (templates[asset] ?? template).clone(recursive: true)
        } catch {
            inFlight[asset] = nil
            throw error
        }
    }

    private static func touch(_ asset: String, isCosmetic: Bool) {
        guard !isCosmetic else { return }
        recentCharacters.removeAll { $0 == asset }
        recentCharacters.append(asset)
        while recentCharacters.count > max(characterCapacity, 1) {
            templates[recentCharacters.removeFirst()] = nil
        }
    }

    /// Memory-warning / test hook.
    static func purge() { templates.removeAll(); recentCharacters.removeAll(); stats = (0, 0) }
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
