import Foundation
import RealityKit
import simd

// Geometric wardrobe fit validator (MOL-03 fits). Pure RealityKit + Foundation so the same file drives the XCTest
// (`MOL03WardrobeFitValidationTests`) and the offline solver / contact-sheet tool. All distances are metres in the
// character's world space (Originals are ~10 cm tall, so 0.002 = 2 mm).

enum MolibooFitKind: String, CaseIterable, Sendable {
    case surface     // sits on the body: hats, hair, face, wings/backpacks, shoes, pins
    case wrap        // goes around the body: tops, bottoms, outerwear, capes, necklaces, scarves
    case held        // touches the body side, like it's being held
    case pet         // stands on the ground next to the character
    case aura        // effect around the character (translucent, may orbit through)
    case background  // backdrop behind the character

    static func of(itemID: String, slot: String, anchor: String) -> MolibooFitKind {
        switch slot {
        case "background": return .background
        case "aura": return .aura
        case "pet": return .pet
        case "held": return .held
        case "top", "outerwear", "bottom": return .wrap
        case "back": return anchor == "anchor_base" ? .wrap : .surface
        case "accessory":
            return ["acc.bowtie", "acc.firstpin", "acc.heartpin", "acc.starpin", "acc.necktie"].contains(itemID) ? .surface : .wrap
        case "seasonal":
            if ["sea.spookycape", "sea.winterscarf"].contains(itemID) { return .wrap }
            return anchor == "anchor_base" ? .aura : .surface
        default: return .surface
        }
    }
}

struct MolibooFitLimits: Sendable {
    static let maxGap: Float = 0.002            // no floating gaps over 2 mm
    static let deepDepth: Float = 0.003         // "deep" = more than 3 mm inside the body
    static let maxDetached: Float = 0.0015      // an item's parts must stay joined (Signature Cap brim/dome)
    static func maxBuriedFraction(_ k: MolibooFitKind) -> Float { k == .wrap ? 0.25 : 0.5 }
    static func maxDeepFraction(_ k: MolibooFitKind) -> Float {
        switch k { case .surface: 0.03; case .wrap: 0.05; case .held, .pet: 0.02; case .aura: 0.2; case .background: 0.01 }
    }
}

struct MolibooFitMetrics: Sendable {
    var kind: MolibooFitKind
    var gap: Float              // min signed distance item → body surface (+ outside, − inside)
    var deepFraction: Float     // item surface fraction deeper than 3 mm inside the body
    var maxDepth: Float
    var detached: Float         // worst distance of an item part from the body and the item's other parts
    var buriedFraction: Float   // item surface fraction under the body surface at all (hidden from view)
    var medianStandoff: Float   // median signed distance (garments should hug, not balloon)
    var centerY: Float = 0.5    // item centre height as a share of body height (0 = ground, 1 = top)
    var slot: String = ""
    var frontCover: Float = 0   // backgrounds: share of the backdrop sitting in front of the character (a dome over it)
    var groundGap: Float        // item min Y above the character's base (ground)
    var ratioW: Float           // item width / body width
    var ratioH: Float           // item height / body height
    var ratioMax: Float
    var failures: [String] = []
    var passed: Bool { failures.isEmpty }
}

struct MolibooSurfacePoint { var p: SIMD3<Float>; var n: SIMD3<Float> }

/// Samples every model part under `entity` (vertices + triangle centroids/edge midpoints) in world space.
@MainActor func molibooSurfaceParts(_ entity: Entity, densify: Bool = true, maxPerPart: Int = .max) -> [[MolibooSurfacePoint]] {
    var out: [[MolibooSurfacePoint]] = []
    func walk(_ x: Entity) {
        if let m = x.components[ModelComponent.self] {
            let w = x.transformMatrix(relativeTo: nil)
            for inst in m.mesh.contents.instances {
                guard let model = m.mesh.contents.models[inst.model] else { continue }
                let t = w * inst.transform
                for part in model.parts {
                    let P = part.positions.elements.map { v -> SIMD3<Float> in let h = t * SIMD4(v, 1); return SIMD3(h.x, h.y, h.z) }
                    var pts: [MolibooSurfacePoint] = []
                    if let tri = part.triangleIndices?.elements, tri.count >= 3 {
                        var vn = [SIMD3<Float>](repeating: .zero, count: P.count)
                        for i in stride(from: 0, to: tri.count - 2, by: 3) {
                            let ia = Int(tri[i]), ib = Int(tri[i + 1]), ic = Int(tri[i + 2])
                            let a = P[ia], b = P[ib], c = P[ic]
                            let n = simd_cross(b - a, c - a)
                            vn[ia] += n; vn[ib] += n; vn[ic] += n
                            if densify {
                                let nn = simd_length(n) > 0 ? simd_normalize(n) : .zero
                                // Barycentric grid so long, thin triangles (cone sides, brims) are sampled every ~2 mm.
                                let edge = max(simd_distance(a, b), simd_distance(b, c), simd_distance(a, c))
                                if edge <= 0.003 { pts.append(.init(p: (a + b + c) / 3, n: nn)); continue }
                                let k = min(30, Int((edge / 0.002).rounded(.up)))
                                for u in 0...k { for v in 0...(k - u) where !(u == 0 && v == 0) && !(u == k) && !(v == k) {
                                    let fu = Float(u) / Float(k), fv = Float(v) / Float(k)
                                    pts.append(.init(p: a + (b - a) * fu + (c - a) * fv, n: nn))
                                } }
                            }
                        }
                        for i in P.indices { pts.append(.init(p: P[i], n: simd_length(vn[i]) > 0 ? simd_normalize(vn[i]) : .zero)) }
                    } else {
                        pts = P.map { .init(p: $0, n: .zero) }
                    }
                    if pts.count > maxPerPart { let st = Double(pts.count) / Double(maxPerPart); pts = (0..<maxPerPart).map { pts[Int(Double($0) * st)] } }
                    if !pts.isEmpty { out.append(pts) }
                }
            }
        }
        for c in x.children where !c.name.hasPrefix("Wardrobe_") && !c.name.hasPrefix("Cosmetic_") && !c.name.hasPrefix("Fit_") { walk(c) }
    }
    walk(entity)
    return out
}

/// The character's surface as a spatial hash for nearest-point / signed-distance queries.
final class MolibooFitBody {
    let points: [MolibooSurfacePoint]
    let lo: SIMD3<Float>, hi: SIMD3<Float>
    private let cell: Float = 0.003
    private var map: [SIMD3<Int32>: [Int32]] = [:]
    private let coarseCell: Float = 0.015
    private var coarse: [SIMD3<Int32>: [Int32]] = [:]
    var extent: SIMD3<Float> { hi - lo }
    var center: SIMD3<Float> { (lo + hi) / 2 }

    @MainActor convenience init(character: Entity) { self.init(points: molibooSurfaceParts(character).flatMap { $0 }) }

    init(points: [MolibooSurfacePoint]) {
        self.points = points
        var l = points.first?.p ?? .zero, h = l
        for q in points { l = simd_min(l, q.p); h = simd_max(h, q.p) }
        lo = l; hi = h
        for (i, q) in points.enumerated() {
            map[key(q.p), default: []].append(Int32(i))
            if i % 3 == 0 { coarse[ckey(q.p), default: []].append(Int32(i)) }
        }
    }

    private func ckey(_ p: SIMD3<Float>) -> SIMD3<Int32> {
        SIMD3(Int32((p.x / coarseCell).rounded(.down)), Int32((p.y / coarseCell).rounded(.down)), Int32((p.z / coarseCell).rounded(.down)))
    }

    /// Coarse signed distance for points far from the surface (deep inside or well clear of it).
    private func coarseSigned(_ p: SIMD3<Float>) -> Float {
        let k = ckey(p); var best = Float.infinity; var bi: Int32 = -1
        for r: Int32 in 0...3 {
            for dx: Int32 in -r...r { for dy: Int32 in -r...r { for dz: Int32 in -r...r where max(abs(dx), abs(dy), abs(dz)) == r {
                guard let l = coarse[k &+ SIMD3(dx, dy, dz)] else { continue }
                for i in l { let d = simd_distance_squared(points[Int(i)].p, p); if d < best { best = d; bi = i } }
            } } }
            if bi >= 0, best.squareRoot() <= Float(r) * coarseCell { break }
        }
        if bi < 0 { for i in stride(from: 0, to: points.count, by: 5) { let d = simd_distance_squared(points[i].p, p); if d < best { best = d; bi = Int32(i) } } }
        guard bi >= 0 else { return .infinity }
        let q = points[Int(bi)]; let d = best.squareRoot()
        return simd_dot(p - q.p, q.n) < 0 ? -d : d
    }

    private func key(_ p: SIMD3<Float>) -> SIMD3<Int32> {
        SIMD3(Int32((p.x / cell).rounded(.down)), Int32((p.y / cell).rounded(.down)), Int32((p.z / cell).rounded(.down)))
    }

    /// Signed distance to the nearest body sample (− inside), or nil if nothing within ~12 mm.
    func signedDistance(_ p: SIMD3<Float>) -> Float? {
        let k = key(p); var best = Float.infinity; var bi: Int32 = -1
        // Grow the search shell by shell; stop once the best hit is closer than any unvisited cell can be.
        for r: Int32 in 0...4 {
            for dx: Int32 in -r...r { for dy: Int32 in -r...r { for dz: Int32 in -r...r where max(abs(dx), abs(dy), abs(dz)) == r {
                guard let l = map[k &+ SIMD3(dx, dy, dz)] else { continue }
                for i in l { let d = simd_distance_squared(points[Int(i)].p, p); if d < best { best = d; bi = i } }
            } } }
            if bi >= 0, best.squareRoot() <= Float(r) * cell { break }
        }
        guard bi >= 0 else { return nil }
        let q = points[Int(bi)]; let d = best.squareRoot()
        return simd_dot(p - q.p, q.n) < 0 ? -d : d
    }

    /// Signed distance anywhere: fine search near the surface, coarse beyond ~12 mm.
    func distance(_ p: SIMD3<Float>) -> Float { signedDistance(p) ?? coarseSigned(p) }

    /// Body width/depth in a horizontal band (used for garment aspect).
    func band(_ y0: Float, _ y1: Float) -> SIMD2<Float> {
        var l = SIMD2<Float>(repeating: .infinity), h = SIMD2<Float>(repeating: -.infinity)
        for q in points where q.p.y >= y0 && q.p.y <= y1 { l = simd_min(l, SIMD2(q.p.x, q.p.z)); h = simd_max(h, SIMD2(q.p.x, q.p.z)) }
        return l.x.isFinite ? h - l : SIMD2(extent.x, extent.z)
    }
}

@MainActor enum MolibooFitValidator {
    /// Measures an item that is already attached to its anchor with its final transform.
    static func measure(item: Entity, body: MolibooFitBody, kind: MolibooFitKind, slot: String = "", maxPerPart: Int = 12000) -> MolibooFitMetrics {
        let parts = molibooSurfaceParts(item, densify: kind != .background && kind != .aura, maxPerPart: maxPerPart)
        let all = parts.flatMap { $0 }
        guard !all.isEmpty else {
            return .init(kind: kind, gap: .infinity, deepFraction: 0, maxDepth: 0, detached: 0, buriedFraction: 0, medianStandoff: 0, groundGap: 0, ratioW: 0, ratioH: 0, ratioMax: 0, failures: ["empty"])
        }
        var gap = Float.infinity, deep = 0, buried = 0, maxDepth: Float = 0
        var lo = all[0].p, hi = lo
        var partGap = [Float](repeating: .infinity, count: parts.count)
        var standoffs: [Float] = []
        let stride0 = max(1, all.count / 600)
        var n = 0
        for (pi, pp) in parts.enumerated() {
            for q in pp {
                lo = simd_min(lo, q.p); hi = simd_max(hi, q.p)
                let s = body.distance(q.p)
                gap = min(gap, s); partGap[pi] = min(partGap[pi], max(s, 0))
                if s < -MolibooFitLimits.deepDepth { deep += 1 }
                if s < -0.0005 { buried += 1 }
                maxDepth = max(maxDepth, -s)
                if n % stride0 == 0 { standoffs.append(s) }
                n += 1
            }
        }
        standoffs.sort()
        var front = 0
        if kind == .background {
            let half = body.extent.x / 2, cx = body.center.x, midY = body.lo.y + body.extent.y * 0.5
            for q in all where q.p.z > body.hi.z && abs(q.p.x - cx) < half && q.p.y > midY { front += 1 }
        }
        var detached: Float = 0
        if parts.count > 1, kind == .surface || kind == .wrap {
            for (i, pp) in parts.enumerated() where partGap[i] > MolibooFitLimits.maxDetached {
                let others = MolibooFitBody(points: parts.enumerated().filter { $0.offset != i }.flatMap { $0.element })
                var best = partGap[i]
                for q in pp { if let s = others.signedDistance(q.p) { best = min(best, abs(s)) }; if best <= MolibooFitLimits.maxDetached { break } }
                detached = max(detached, best.isFinite ? best : 0.0125)
            }
        }
        let e = hi - lo, b = body.extent
        var m = MolibooFitMetrics(kind: kind, gap: gap, deepFraction: Float(deep) / Float(all.count), maxDepth: maxDepth, detached: detached,
                                  buriedFraction: Float(buried) / Float(all.count), medianStandoff: standoffs.isEmpty ? 0 : standoffs[standoffs.count / 2],
                                  groundGap: lo.y - body.lo.y, ratioW: e.x / b.x, ratioH: e.y / b.y, ratioMax: max(e.x / b.x, e.y / b.y, e.z / b.z))
        m.slot = slot
        m.frontCover = Float(front) / Float(all.count)
        m.centerY = ((lo.y + hi.y) / 2 - body.lo.y) / max(1e-4, b.y)
        m.failures = failures(m)
        return m
    }

    static func failures(_ m: MolibooFitMetrics) -> [String] {
        var f: [String] = []
        let deepOK = m.deepFraction <= MolibooFitLimits.maxDeepFraction(m.kind)
        switch m.kind {
        case .surface, .wrap, .held:
            if m.gap > MolibooFitLimits.maxGap { f.append(String(format: "floating gap %.1f mm", m.gap * 1000)) }
            if !deepOK { f.append(String(format: "clips %.0f%% deep (max %.1f mm)", m.deepFraction * 100, m.maxDepth * 1000)) }
            if m.detached > MolibooFitLimits.maxDetached { f.append(String(format: "detached part %.1f mm", m.detached * 1000)) }
            if m.buriedFraction > MolibooFitLimits.maxBuriedFraction(m.kind) { f.append(String(format: "hidden inside body (%.0f%%)", m.buriedFraction * 100)) }
            if m.kind == .wrap {
                if m.ratioH < 0.05 { f.append(String(format: "too thin to read (%.2f× body height)", m.ratioH)) }
                let band: ClosedRange<Float> = m.slot == "bottom" ? 0...0.5 : (m.slot == "accessory" ? 0.25...0.9 : 0.1...0.8)
                if !band.contains(m.centerY) { f.append(String(format: "sits at the wrong height (%.0f%% up the body)", m.centerY * 100)) }
            }
            if m.kind == .wrap, m.medianStandoff > 0.008 { f.append(String(format: "baggy (%.1f mm off body)", m.medianStandoff * 1000)) }
            if m.kind == .held, m.groundGap < -0.002 { f.append("below ground") }
        case .pet:
            if abs(m.groundGap) > MolibooFitLimits.maxGap { f.append(String(format: "not on ground (%.1f mm)", m.groundGap * 1000)) }
            if m.gap > 0.02 { f.append(String(format: "too far from character (%.0f mm)", m.gap * 1000)) }
            if !deepOK { f.append("clips into character") }
        case .aura:
            if !deepOK { f.append(String(format: "clips %.0f%% deep", m.deepFraction * 100)) }
            if m.gap > 0.04 { f.append(String(format: "drifts %.0f mm away", m.gap * 1000)) }
        case .background:
            if !deepOK { f.append("cuts through character") }
            if m.frontCover > 0.08 { f.append(String(format: "covers the character (%.0f%% in front)", m.frontCover * 100)) }
        }
        // Proportions vs the body.
        let (lo, hi): (Float, Float) = {
            switch m.kind {
            case .surface: return (0.03, 1.35)
            case .wrap: return (0.5, 1.5)
            case .held: return (0.1, 1.1)
            case .pet: return (0.15, 0.85)
            case .aura: return (0.15, 2.6)
            case .background: return (1.5, 6)
            }
        }()
        if m.ratioMax < lo || m.ratioMax > hi { f.append(String(format: "scale off (%.2f× body)", m.ratioMax)) }
        return f
    }

    /// Applies a table/manifest fit exactly as `MolibooWardrobeRig.equip` / `MolibooSceneController.equip` do.
    static func apply(item: Entity, to anchor: Entity, offset: [Float], rotationDegrees: [Float], scale: Float, stretch: [Float]?, manifestCorrection: Bool) {
        anchor.addChild(item)
        let r = rotationDegrees.map { $0 * .pi / 180 } + [0, 0, 0]
        var q = simd_quatf(angle: r[2], axis: [0, 0, 1]) * simd_quatf(angle: r[1], axis: [0, 1, 0]) * simd_quatf(angle: r[0], axis: [1, 0, 0])
        if manifestCorrection { q = q * simd_quatf(angle: .pi / 2, axis: [1, 0, 0]) }
        let o = offset + [0, 0, 0]
        let s = (stretch ?? [1, 1, 1]) + [1, 1, 1]
        item.transform = Transform(scale: SIMD3(s[0], s[1], s[2]) * scale, rotation: q, translation: [o[0], o[1], o[2]])
    }
}
