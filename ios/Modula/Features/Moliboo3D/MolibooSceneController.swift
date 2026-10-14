import Foundation
import Observation
import RealityKit
import simd

/// Owns the live Pebble entity graph: expressions, idle animation, equipment and interaction reactions.
@MainActor @Observable
final class MolibooSceneController {
    let descriptor: MolibooCharacterDescriptor
    private(set) var root = Entity()
    private(set) var character: Entity?
    private(set) var expression: MolibooExpression = .idle
    private(set) var equipped: [String: Entity] = [:]   // wardrobe item id → entity
    private(set) var loadFailed = false
    // Diagnostics (cheap; surfaced only by the DEBUG state probe for XCUITest acceptance).
    private(set) var loadMillis: Double = 0
    private(set) var meshCount = 0
    private(set) var clipsPlayed = 0
    private(set) var lastAction = ""
    private(set) var frameCount = 0
    private(set) var frameTimeSum: Double = 0
    private(set) var frameTimeMax: Double = 0
    /// Retained frame-timing subscription (a dropped EventSubscription crashes on scene teardown).
    var frameSubscription: EventSubscription?
    func recordFrame(_ dt: TimeInterval) {
        guard dt > 0, dt < 1 else { return }
        frameCount += 1; frameTimeSum += dt; frameTimeMax = max(frameTimeMax, dt)
    }
    private var idleTask: Task<Void, Never>?
    var yaw: Float = 0 { didSet { root.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]) } }

    static let accessoryOrientationCorrection = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])

    init(descriptor: MolibooCharacterDescriptor) {
        self.descriptor = descriptor
        let camera = PerspectiveCamera()
        camera.name = "Moliboo_Camera"
        camera.camera.fieldOfViewInDegrees = 40
        camera.look(at: [0, 0.03, 0], from: [0, 0.08, 0.42], relativeTo: nil)
        cameraEntity = camera
    }
    /// Added alongside `root` (not under it) so drag-yaw rotates Pebble, not the camera.
    let cameraEntity: PerspectiveCamera

    func load() async {
        let t0 = ContinuousClock.now
        defer { let d = ContinuousClock.now - t0; loadMillis = Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15 }
        do {
            guard let asset = descriptor.asset else { loadFailed = true; return }
            let e = try await MolibooAssetLoader.loadEntity(asset)
            e.name = "Pebble_Root"
            root.addChild(e)
            character = e
            meshCount = Self.countMeshes(e)
            let bounds = e.visualBounds(relativeTo: root)
            // Center horizontally, sit on the ground plane, scale to ~0.2 m wide for preview.
            let s = 0.2 / max(bounds.extents.x, 0.001)
            e.scale = [s, s, s]
            e.position = [-bounds.center.x * s, -bounds.min.y * s - 0.05, -bounds.center.z * s]
            e.generateCollisionShapes(recursive: true)
            e.components.set(InputTargetComponent())
            startIdle()
        } catch {
            loadFailed = true
        }
    }

    private static func countMeshes(_ e: Entity) -> Int {
        (e.components[ModelComponent.self] == nil ? 0 : 1) + e.children.reduce(0) { $0 + countMeshes($1) }
    }

    func anchor(_ name: String) -> Entity? { character?.findEntity(named: name) }
    private func part(_ name: String) -> Entity? { character?.findEntity(named: name) }

    // MARK: Expressions
    // Transform-driven on face parts (deterministic, no dependency on USD skel binding). The USDZ also carries
    // per-part blend shapes (blink/happy/sleepy/excited/surprised, mouth happy/excited/surprised/sleepy/sad/pout)
    // which the baked clips drive; see playClip.
    private static let eyeParts = ["Pebble_Eye_L", "Pebble_Eye_R", "Pebble_Iris_L", "Pebble_Iris_R"]
    private static let shineParts = ["Pebble_EyeShine_L", "Pebble_EyeShine_R", "Pebble_EyeShine2_L", "Pebble_EyeShine2_R"]

    func setExpression(_ e: MolibooExpression) {
        if e == .blink { blink(); return }
        expression = e
        if playClip(e.clipName, loop: true) { return }   // baked blend-shape pose (^ arcs, open mouth, …)
        // Eye/iris/shine discs: local X = width, Y = height on the face, Z = depth (surface normal).
        // Mouth: local X = width, Z = height, Y = depth.
        let eye: SIMD3<Float>, shine: SIMD3<Float>, mouth: SIMD3<Float>
        switch e {
        case .idle, .blink: eye = [1, 1, 1]; shine = [1, 1, 1]; mouth = [1, 1, 1]
        case .happy: eye = [1.05, 0.3, 1]; shine = [0.01, 0.01, 1]; mouth = [1.3, 1, 2.2]
        case .excited: eye = [1.18, 1.18, 1]; shine = [1.25, 1.25, 1]; mouth = [1.1, 1, 4.0]
        case .surprised: eye = [0.88, 1.08, 1]; shine = [1, 1, 1]; mouth = [0.42, 1, 2.6]
        case .sleepy: eye = [1, 0.45, 1]; shine = [0.4, 0.4, 1]; mouth = [0.6, 1, 0.3]
        case .sad: eye = [1, 0.9, 1]; shine = [1, 1, 1]; mouth = [1, 1, -1]
        }
        Self.eyeParts.compactMap(part).forEach { animate($0, scale: eye, duration: 0.15) }
        Self.shineParts.compactMap(part).forEach { animate($0, scale: shine, duration: 0.15) }
        if let m = part("Pebble_Mouth") { animate(m, scale: mouth, duration: 0.18) }
    }

    func blink() {
        if playClip("blink") { return }
        let parts = (Self.eyeParts + Self.shineParts).compactMap(part)
        let restore = parts.map { $0.transform.scale }
        parts.forEach { animate($0, scale: $0.transform.scale * SIMD3<Float>(1, 0.08, 1), duration: 0.07) }
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            for (p, s) in zip(parts, restore) { self.animate(p, scale: s, duration: 0.09) }
        }
    }

    /// Plays a baked clip (idle_bob / blink / wobble / tap) from the USD timeline. Returns false if unavailable,
    /// so callers can fall back to the procedural transform animation.
    @discardableResult
    func playClip(_ name: String, loop: Bool = false) -> Bool {
        guard let c = character, let clip = descriptor.clips[name], let source = c.availableAnimations.first else { return false }
        let fps = Double(descriptor.fps)
        let view = AnimationView(source: source.definition, trimStart: Double(clip.start - 1) / fps, trimEnd: Double(clip.end - 1) / fps)
        guard let resource = try? AnimationResource.generate(with: view) else { return false }
        c.playAnimation(loop ? resource.repeat() : resource, transitionDuration: 0.12)
        clipsPlayed += 1; if name != "blink" { lastAction = "clip:" + name }   // idle auto-blink must not mask user actions
        return true
    }

    func wobble() {
        defer { lastAction = "wobble" }
        if playClip("wobble") { return }
        guard let c = character else { return }
        let base = c.transform
        Task {
            for angle: Float in [0.12, -0.10, 0.06, 0] {
                var t = base; t.rotation = simd_quatf(angle: angle, axis: [0, 0, 1]) * base.rotation
                c.move(to: t, relativeTo: c.parent, duration: 0.12, timingFunction: .easeInOut)
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    func bounce() {
        if playClip("tap") { return }
        guard let c = character else { return }
        let base = c.transform
        Task {
            var up = base; up.translation.y += 0.04; up.scale *= SIMD3<Float>(0.95, 1.08, 0.95)
            c.move(to: up, relativeTo: c.parent, duration: 0.16, timingFunction: .easeOut)
            try? await Task.sleep(for: .milliseconds(160))
            var squash = base; squash.scale *= SIMD3<Float>(1.08, 0.9, 1.08)
            c.move(to: squash, relativeTo: c.parent, duration: 0.14, timingFunction: .easeIn)
            try? await Task.sleep(for: .milliseconds(140))
            c.move(to: base, relativeTo: c.parent, duration: 0.12, timingFunction: .easeOut)
        }
    }

    /// Tap reaction: micro-smile + wobble ("I am here.")
    func react() {
        setExpression(.happy); bounce(); lastAction = "react"
        Task { try? await Task.sleep(for: .seconds(1.2)); if self.expression == .happy { self.setExpression(.idle) } }
    }

    private func startIdle() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 2.5...4.5)))
                self?.blink()
            }
        }
    }
    func stop() { idleTask?.cancel(); frameSubscription?.cancel(); frameSubscription = nil }

    private func animate(_ e: Entity, scale: SIMD3<Float>, duration: TimeInterval) {
        var t = e.transform; t.scale = scale
        e.move(to: t, relativeTo: e.parent, duration: duration, timingFunction: .easeInOut)
    }

    // MARK: Equipment
    /// Manifest-wide cosmetic lookup (asset per wardrobe item); set by the preview after loading the manifest.
    var cosmetics: [MolibooCosmeticDescriptor] = []

    func compatibility(wardrobeItemID id: String) -> MolibooCompatibility {
        guard cosmetics.contains(where: { $0.wardrobeItemID == id }) else { return .notCompatible }
        return descriptor.compatibility(forWardrobeItem: id)
    }
    func isSupported(wardrobeItemID id: String) -> Bool { compatibility(wardrobeItemID: id).isCompatible }

    /// Local orientation for an attachment: config rotation (authoring frame) × the Y-up export correction.
    static func attachmentOrientation(_ cfg: MolibooAttachmentConfig) -> simd_quatf {
        let r = cfg.rotationDegrees.map { $0 * .pi / 180 } + [0, 0, 0]
        let q = simd_quatf(angle: r[2], axis: [0, 0, 1]) * simd_quatf(angle: r[1], axis: [0, 1, 0]) * simd_quatf(angle: r[0], axis: [1, 0, 0])
        return q * accessoryOrientationCorrection
    }

    @discardableResult
    func equip(wardrobeItemID id: String) async -> Bool {
        if equipped[id] != nil { return true }
        guard case .compatible(let cfg) = compatibility(wardrobeItemID: id),
              let cosmetic = cosmetics.first(where: { $0.wardrobeItemID == id }),
              let anchor = anchor(cfg.anchor),
              let e = try? await MolibooAssetLoader.loadEntity(cosmetic.asset) else { return false }
        e.name = "Cosmetic_\(id)"
        anchor.addChild(e)   // child of the anchor ⇒ follows rotation, bob, wobble and tap animation
        e.transform = .identity
        // Both USDZs carry a root -90° X (Z-up → Y-up) conversion; the anchor already inherits Pebble's,
        // so the correction cancels it once, otherwise the cosmetic would be rotated twice.
        e.orientation = Self.attachmentOrientation(cfg)
        let o = cfg.offset + [0, 0, 0]
        e.position = [o[0], o[1], o[2]]
        e.scale = [cfg.scale, cfg.scale, cfg.scale]
        equipped[id] = e
        return true
    }

    func unequip(wardrobeItemID id: String) {
        equipped.removeValue(forKey: id)?.removeFromParent()
    }

    /// Apply the persisted outfit: only items with a 3D asset are shown, others are ignored (not removed from the outfit).
    func sync(outfitItemIDs ids: [String]) async {
        let wanted = Set(ids.filter(isSupported))
        for id in equipped.keys where !wanted.contains(id) { unequip(wardrobeItemID: id) }
        for id in wanted { await equip(wardrobeItemID: id) }
    }
}
