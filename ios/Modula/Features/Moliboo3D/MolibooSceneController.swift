import Foundation
import Observation
import RealityKit
import simd
import UIKit

/// Owns the live entity graph of one Moliboo character: expressions, idle animation, equipment and interaction reactions.
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
    private(set) var loadWasCached = false
    private(set) var meshCount = 0
    private(set) var clipsPlayed = 0
    private(set) var lastAction = ""
    private(set) var reactCount = 0
    @ObservationIgnored private(set) var frameCount = 0
    @ObservationIgnored private(set) var frameTimeSum: Double = 0
    @ObservationIgnored private(set) var frameTimeMax: Double = 0
    /// Retained frame-timing subscription (a dropped EventSubscription crashes on scene teardown).
    @ObservationIgnored var frameSubscription: EventSubscription?
    func recordFrame(_ dt: TimeInterval) {
        guard dt > 0, dt < 1 else { return }
        frameCount += 1; frameTimeSum += dt; frameTimeMax = max(frameTimeMax, dt)
    }
    private var idleTask: Task<Void, Never>?
    /// Teardown state (MOL-02 stability track): once stopped, nothing may start a clip, a move or a queued task,
    /// because RealityKit can otherwise tick an animation timebase whose clock went away with the scene.
    @ObservationIgnored private(set) var isStopped = false
    @ObservationIgnored private var animationTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var playbacks: [AnimationPlaybackController] = []

    /// Queued animation work is tracked so `stop()` can cancel it; every body re-checks `isStopped` after sleeping.
    private func spawn(_ body: @escaping @MainActor (MolibooSceneController) async -> Void) {
        guard !isStopped else { return }
        animationTasks.removeAll { $0.isCancelled }
        animationTasks.append(Task { [weak self] in
            guard let self, !self.isStopped else { return }
            await body(self)
        })
        if animationTasks.count > 32 { animationTasks.removeFirst(animationTasks.count - 32) }
    }
    private func track(_ c: AnimationPlaybackController) {
        playbacks.removeAll { $0.isComplete || $0.isStopped }
        playbacks.append(c)
    }
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
            loadWasCached = MolibooAssetLoader.isCached(asset)
            let e = try await MolibooAssetLoader.loadEntity(asset)
            guard !isStopped, !Task.isCancelled else { return }   // view left / cancelled: never attach to a torn-down scene
            Self.disableShadows(e)
            e.name = descriptor.displayName + "_Root"
            root.addChild(e)
            character = e
            meshCount = Self.countMeshes(e)
            let bounds = e.visualBounds(relativeTo: root)
            // Center horizontally, sit on the ground plane, scale to ~0.2 m wide for preview.
            let s = 0.2 / max(bounds.extents.x, 0.001)
            e.scale = [s, s, s]
            e.position = [-bounds.center.x * s, -bounds.min.y * s - 0.05, -bounds.center.z * s]
            Self.attachContactShadow(under: e, on: root)
            e.generateCollisionShapes(recursive: true)
            e.components.set(InputTargetComponent())
            startIdle()
        } catch {
            loadFailed = true
        }
    }

    /// Stability experiment (MOL-02 track): no light in the scene uses shadows, but RealityKit's MeshShadowSystem still tracks
    /// every model. Opting out removes that system from the per-open add/remove path.
    static func disableShadows(_ e: Entity) {
        if e.components[ModelComponent.self] != nil { e.components.set(DynamicLightShadowComponent(castsShadow: false)) }
        e.children.forEach(disableShadows)
    }

    /// Soft oval under the character. Cheap substitute for the DynamicLightShadow we opted out of; keeps the model grounded.
    static func attachContactShadow(under character: Entity, on root: Entity) {
        let mesh = MeshResource.generatePlane(width: 0.14, depth: 0.09)
        // A plain unlit colour renders as an opaque black rectangle on device (no alpha blending on a colour-only
        // material). Use a soft radial-falloff texture with transparent blending so it reads as an oval contact shadow.
        var mat = UnlitMaterial()
        if let tex = contactShadowTexture() {
            mat.color = .init(tint: .white, texture: .init(tex))
            mat.blending = .transparent(opacity: .init(scale: 1, texture: .init(tex)))
        } else {
            return   // no shadow beats a black slab
        }
        let blob = ModelEntity(mesh: mesh, materials: [mat])
        blob.name = "ContactShadow"
        blob.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        let bounds = character.visualBounds(relativeTo: root)
        blob.position = [bounds.center.x, bounds.min.y + 0.0005, bounds.center.z]
        root.addChild(blob)
    }

    /// 64×64 radial falloff (black, alpha 0.28 → 0), cached.
    private static var cachedShadowTexture: TextureResource?
    private static func contactShadowTexture() -> TextureResource? {
        if let t = cachedShadowTexture { return t }
        let n = 64
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                    colors: [CGColor(red: 0, green: 0, blue: 0, alpha: 0.28), CGColor(red: 0, green: 0, blue: 0, alpha: 0)] as CFArray,
                                    locations: [0, 1]) else { return nil }
        let c = CGPoint(x: CGFloat(n) / 2, y: CGFloat(n) / 2)
        ctx.drawRadialGradient(grad, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(n) / 2, options: [])
        guard let img = ctx.makeImage(),
              let t = try? TextureResource(image: img, options: .init(semantic: .color)) else { return nil }
        cachedShadowTexture = t
        return t
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
    /// Part names follow the builders' `<DisplayName>_` prefix convention (Pebble_Eye_L, Pip_Eye_L, …).
    private var partPrefix: String { descriptor.displayName + "_" }
    private var eyeParts: [String] { ["Eye_L", "Eye_R", "Iris_L", "Iris_R"].map { partPrefix + $0 } }
    private var shineParts: [String] { ["EyeShine_L", "EyeShine_R", "EyeShine2_L", "EyeShine2_R"].map { partPrefix + $0 } }

    func setExpression(_ e: MolibooExpression) {
        guard !isStopped else { return }
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
        eyeParts.compactMap(part).forEach { animate($0, scale: eye, duration: 0.15) }
        shineParts.compactMap(part).forEach { animate($0, scale: shine, duration: 0.15) }
        if let m = part(partPrefix + "Mouth") { animate(m, scale: mouth, duration: 0.18) }
    }

    func blink() {
        guard !isStopped else { return }
        if playClip("blink") { return }
        let parts = (eyeParts + shineParts).compactMap(part)
        let restore = parts.map { $0.transform.scale }
        parts.forEach { animate($0, scale: $0.transform.scale * SIMD3<Float>(1, 0.08, 1), duration: 0.07) }
        spawn { me in
            try? await Task.sleep(for: .milliseconds(120))
            guard !me.isStopped else { return }
            for (p, s) in zip(parts, restore) { me.animate(p, scale: s, duration: 0.09) }
        }
    }

    /// Plays a baked clip (idle_bob / blink / wobble / tap) from the USD timeline. Returns false if unavailable,
    /// so callers can fall back to the procedural transform animation.
    @discardableResult
    func playClip(_ name: String, loop: Bool = false) -> Bool {
        guard !isStopped, let c = character, let clip = descriptor.clips[name], let source = c.availableAnimations.first else { return false }
        let fps = Double(descriptor.fps)
        let view = AnimationView(source: source.definition, trimStart: Double(clip.start - 1) / fps, trimEnd: Double(clip.end - 1) / fps)
        guard let resource = try? AnimationResource.generate(with: view) else { return false }
        track(c.playAnimation(loop ? resource.repeat() : resource, transitionDuration: 0.12))
        clipsPlayed += 1; if name != "blink" { lastAction = "clip:" + name }   // idle auto-blink must not mask user actions
        return true
    }

    func wobble() {
        guard !isStopped else { return }
        defer { lastAction = "wobble" }
        if playClip("wobble") { return }
        guard let c = character else { return }
        let base = c.transform
        spawn { me in
            for angle: Float in [0.12, -0.10, 0.06, 0] {
                guard !me.isStopped else { return }
                var t = base; t.rotation = simd_quatf(angle: angle, axis: [0, 0, 1]) * base.rotation
                me.track(c.move(to: t, relativeTo: c.parent, duration: 0.12, timingFunction: .easeInOut))
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    func bounce() {
        guard !isStopped else { return }
        if playClip("tap") { return }
        guard let c = character else { return }
        let base = c.transform
        spawn { me in
            var up = base; up.translation.y += 0.04; up.scale *= SIMD3<Float>(0.95, 1.08, 0.95)
            me.track(c.move(to: up, relativeTo: c.parent, duration: 0.16, timingFunction: .easeOut))
            try? await Task.sleep(for: .milliseconds(160))
            guard !me.isStopped else { return }
            var squash = base; squash.scale *= SIMD3<Float>(1.08, 0.9, 1.08)
            me.track(c.move(to: squash, relativeTo: c.parent, duration: 0.14, timingFunction: .easeIn))
            try? await Task.sleep(for: .milliseconds(140))
            guard !me.isStopped else { return }
            me.track(c.move(to: base, relativeTo: c.parent, duration: 0.12, timingFunction: .easeOut))
        }
    }

    /// Tap reaction: micro-smile + wobble ("I am here.")
    func react() {
        guard !isStopped else { return }
        setExpression(.happy); bounce(); lastAction = "react"; reactCount += 1
        spawn { me in
            try? await Task.sleep(for: .seconds(1.2))
            if !me.isStopped, me.expression == .happy { me.setExpression(.idle) }
        }
    }

    private func startIdle() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 2.5...4.5)))
                guard !Task.isCancelled else { return }
                self?.blink()
            }
        }
    }
    /// Full teardown, called before the RealityView goes away: no new work, cancel queued tasks, stop every
    /// playback (clips and transform moves) on the character and the cosmetics, then detach the graph from the scene.
    func stop() {
        guard !isStopped else { return }
        isStopped = true
        idleTask?.cancel(); idleTask = nil
        animationTasks.forEach { $0.cancel() }; animationTasks.removeAll()
        playbacks.forEach { $0.stop() }; playbacks.removeAll()
        equipped.values.forEach { $0.stopAllAnimations(recursive: true) }
        character?.stopAllAnimations(recursive: true)
        root.stopAllAnimations(recursive: true)
        frameSubscription?.cancel(); frameSubscription = nil
        root.removeFromParent()
        cameraEntity.removeFromParent()
    }

    private func animate(_ e: Entity, scale: SIMD3<Float>, duration: TimeInterval) {
        guard !isStopped else { return }
        var t = e.transform; t.scale = scale
        track(e.move(to: t, relativeTo: e.parent, duration: duration, timingFunction: .easeInOut))
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
              let e = try? await MolibooAssetLoader.loadEntity(cosmetic.asset, isCosmetic: true) else { return false }
        guard !isStopped, !Task.isCancelled, equipped[id] == nil else { return equipped[id] != nil }
        Self.disableShadows(e)
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
