import Foundation
import RealityKit

/// Repeatable MOL-03 Workstream B benchmark. All numbers are measured by the DEBUG probe / XCUITest harness.
/// Measurement points (section 11):
/// 1. coldLoadMs — first load of a character in the process
/// 2. warmLoadMs — subsequent loads of the same character (expects cache hit)
/// 3. switchMs — time to replace the shown character with another
/// 4. openFootprintMB — process footprint after the first open
/// 5. afterSwitchFootprintMB — after switching away and back
/// 6. afterCapFootprintMB — after equipping the Signature Cap
/// 7. closedFootprintMB — after detaching the stage content
@MainActor
struct MolibooRendererBenchmark {
    struct Sample: Codable {
        var coldLoadMs: Double = 0
        var warmLoadMs: Double = 0
        var switchMs: Double = 0
        var openFootprintMB: Double = 0
        var afterSwitchFootprintMB: Double = 0
        var afterCapFootprintMB: Double = 0
        var closedFootprintMB: Double = 0
        var avgFrameMs: Double = 0
        var maxFrameMs: Double = 0
        var frames: Int = 0
        var cacheHits: Int = 0
        var cacheMisses: Int = 0
    }

    static func footprintMB() -> Double {
        #if DEBUG
        return MOL01Memory.footprintMB()
        #else
        return -1
        #endif
    }

    /// Runs the seven-point suite against a fresh controller for `primary`, then a second character for the switch.
    static func run(primary: String, secondary: String, outfitIDs: [String] = []) async -> Sample {
        var s = Sample()
        guard let m = MolibooRegistry.manifest,
              let d1 = MolibooRegistry.descriptor(for: primary, manifest: m),
              let d2 = MolibooRegistry.descriptor(for: secondary, manifest: m) else { return s }
        MolibooAssetLoader.purge()

        let c1 = MolibooSceneController(descriptor: d1); c1.cosmetics = m.cosmetics
        await c1.load(); s.coldLoadMs = c1.loadMillis; s.openFootprintMB = footprintMB()
        await c1.sync(outfitItemIDs: outfitIDs)
        await c1.equip(wardrobeItemID: MolibooCosmetics.signatureCapID)
        s.afterCapFootprintMB = footprintMB()

        let c2 = MolibooSceneController(descriptor: d2); c2.cosmetics = m.cosmetics
        let t0 = ContinuousClock.now
        await c2.load()
        let d = ContinuousClock.now - t0
        s.switchMs = Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
        s.afterSwitchFootprintMB = footprintMB()

        let c1b = MolibooSceneController(descriptor: d1); c1b.cosmetics = m.cosmetics
        await c1b.load(); s.warmLoadMs = c1b.loadMillis

        c1.stop(); c2.stop(); c1b.stop()
        s.closedFootprintMB = footprintMB()
        s.cacheHits = MolibooAssetLoader.stats.hits
        s.cacheMisses = MolibooAssetLoader.stats.misses
        s.avgFrameMs = c1.frameCount > 0 ? c1.frameTimeSum / Double(c1.frameCount) * 1000 : 0
        s.maxFrameMs = c1.frameTimeMax * 1000
        s.frames = c1.frameCount
        return s
    }
}
