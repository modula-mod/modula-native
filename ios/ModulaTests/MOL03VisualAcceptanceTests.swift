import XCTest
import SwiftUI
import UIKit
@testable import Modula

/// MOL-03B/C visual acceptance: deterministic renders of every Moliboo.
/// - Always runs: Signature Cap fit checks (attached, eyes clear, not clipped) for all wearable characters in a still pose
///   and four animated phases; seven-expression inventory renders for all 115; reaction poses for all 115.
/// - With `MOLIBOO_SNAPSHOT_DIR`: writes the MOL-03 contact sheets (base + capped, small-scale, expressions, reactions,
///   difficult fittings). With `MOLIBOO_FIT_EXPORT`: writes the measured fit profile file.
@MainActor
final class MOL03VisualAcceptanceTests: XCTestCase {
    static let capID = "cap.moliboo.signature"
    static let phases: [Double] = [0.0, 0.7, 1.9, 3.3]
    static let edgeCases = ["aura", "bolt", "echo", "orbit", "rolo", "spindle", "nyx", "vesper", "comfi", "somna"]

    private var snapshotDir: URL? {
        guard let d = ProcessInfo.processInfo.environment["MOLIBOO_SNAPSHOT_DIR"], !d.isEmpty else { return nil }
        let url = URL(fileURLWithPath: d)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var cap: MascotWardrobeItem { MascotWardrobeCatalog.item(id: Self.capID)! }

    // MARK: Signature Cap fitting (100/100 wearable, Legends exempt by design)

    func testSignatureCapFitsEveryWearableMoliboo() throws {
        XCTAssertNotNil(MascotWardrobeCatalog.item(id: Self.capID), "Signature Cap must stay in the catalogue")
        XCTAssertEqual(MascotWardrobeCatalog.item(id: Self.capID)?.rarity, .common, "Signature Cap stays a free Common item")
        var failures: [String] = []
        var measured: [String: MolibooCapFitMeasurement] = [:]
        for kind in ModulaMascotKind.allCases {
            guard kind.supportsWardrobe else {
                // Legends wear their own look: equipping must draw nothing (and never clear the saved outfit).
                let a = MolibooRaster(ModulaMascotFigure(kind: kind, pose: .still(), size: 96))
                let b = MolibooRaster(ModulaMascotFigure(kind: kind, pose: .still(), size: 96, outfit: .solo(cap)))
                if a.diff(b).count > 0 { failures.append("\(kind.rawValue): Legend drew a wardrobe cap") }
                continue
            }
            var worst = MolibooCapFitMeasurement.perfect
            for (i, t) in ([nil] + Self.phases.map { Optional($0) }).enumerated() {
                let pose = t.map { MascotPose(t: $0, amp: 1) } ?? .still()
                let m = MolibooCapFitMeasurement.measure(kind: kind, cap: cap, pose: pose, size: 96)
                if let why = m.failure { failures.append("\(kind.rawValue) [\(i == 0 ? "still" : "t=\(t!)")]: \(why)") }
                worst = worst.worse(m)
            }
            measured[kind.rawValue] = worst
        }
        XCTAssertEqual(measured.count, 100, "100 wearable Moliboos measured")
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
        if let path = ProcessInfo.processInfo.environment["MOLIBOO_FIT_EXPORT"], !path.isEmpty {
            let file = MolibooFitProfiles.export(measured: measured)
            try MolibooFitProfiles.encode(file).write(to: URL(fileURLWithPath: path))
        }
    }

    /// The committed fit file matches what the renderer actually does (catches silent rig drift).
    func testCommittedFitProfilesMatchRig() throws {
        let file = try XCTUnwrap(MolibooFitProfiles.bundled, "moliboo_accessory_fits.json must ship in the bundle")
        XCTAssertEqual(file.profiles.count, 100)
        for kind in ModulaMascotKind.allCases where kind.supportsWardrobe {
            let p = try XCTUnwrap(file.profiles["fit/\(kind.rawValue)"], kind.rawValue)
            let rig = MascotRig.stock(kind)
            XCTAssertEqual(p.characterId, kind.registryID)
            XCTAssertEqual(p.anchor.y, Double(rig.headTop), accuracy: 0.0005, kind.rawValue)
            XCTAssertEqual(p.width, Double(rig.hatWidth), accuracy: 0.0005, kind.rawValue)
            XCTAssertEqual(p.scale, Double(rig.hatScale), accuracy: 0.0005, kind.rawValue)
            XCTAssertTrue(p.followHeadMotion)
            XCTAssertTrue(p.validated, "\(kind.rawValue) fit must be validated")
        }
        for kind in ModulaMascotKind.allCases where !kind.supportsWardrobe {
            XCTAssertNil(file.profiles["fit/\(kind.rawValue)"], "Legends have no wardrobe fit")
        }
        let reg = try XCTUnwrap(MolibooRegistryStore.bundled)
        XCTAssertEqual(MolibooRegistryValidator.validate(reg, fitProfiles: Set(file.profiles.keys)), [])
    }

    // MARK: Expressions and reactions resolve for all 115

    func testSevenExpressionsRenderDistinctlyForEveryMoliboo() throws {
        var flat: [String] = []
        for kind in ModulaMascotKind.allCases {
            let neutral = MolibooRaster(ModulaMascotFigure(kind: kind, pose: MolibooSemanticExpression.neutral.stillPose, size: 64))
            XCTAssertGreaterThan(neutral.opaqueCount, 400, "\(kind.rawValue) neutral renders")
            var distinct = 0
            for e in MolibooSemanticExpression.allCases where e != .neutral {
                let r = MolibooRaster(ModulaMascotFigure(kind: kind, pose: e.stillPose, size: 64))
                if neutral.diff(r).count >= 12 { distinct += 1 }
            }
            if distinct < 6 { flat.append("\(kind.rawValue): only \(distinct)/6 expressions differ from neutral") }
        }
        XCTAssertTrue(flat.isEmpty, flat.joined(separator: "\n"))
    }

    func testRegistryReactionsResolveForEveryMoliboo() throws {
        let reg = try XCTUnwrap(MolibooRegistryStore.bundled)
        for c in reg.characters {
            let kind = try XCTUnwrap(c.kind, c.key)
            for (name, reaction) in c.reactions {
                let mood = try XCTUnwrap(MolibooReactionMoods.mood(named: reaction.mood), "\(c.key).\(name) → \(reaction.mood)")
                let r = MolibooRaster(ModulaMascotFigure(kind: kind, pose: MascotPose(t: 0.4, mood: mood, amp: 1), size: 48))
                XCTAssertGreaterThan(r.opaqueCount, 150, "\(c.key).\(name) renders")
            }
        }
    }

    /// Missing assets never produce a blank: unknown keys fall back to a real built-in Moliboo.
    func testMissingCharacterFallsBackToBuiltIn() {
        XCTAssertNil(ModulaMascotKind(rawValue: "not-a-moliboo"))
        let fallback = ModulaMascotKind(rawValue: "not-a-moliboo") ?? .pip
        XCTAssertGreaterThan(MolibooRaster(ModulaMascotFigure(kind: fallback, pose: .still(), size: 48)).opaqueCount, 150)
    }

    /// Thumbnails at every catalogue size stay recognisable (non-empty, inside the canvas, distinct per character).
    func testSmallScaleAvatarsRenderForEveryMoliboo() {
        var hashes: [Int: Set<String>] = [:]
        var problems: [String] = []
        for kind in ModulaMascotKind.allCases {
            for px in [32, 48, 64, 96, 128] {
                let s = CGFloat(px) / 2.0     // canvas is 2s wide, so a 32 px avatar is s = 16
                let r = MolibooRaster(ModulaMascotFigure(kind: kind, pose: .still(), size: s))
                if r.opaqueCount < px * px / 20 { problems.append("\(kind.rawValue)@\(px): nearly empty") }
                hashes[px, default: []].insert(r.fingerprint)
            }
        }
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "\n"))
        for px in [48, 64, 96, 128] {
            XCTAssertGreaterThanOrEqual(hashes[px]?.count ?? 0, ModulaMascotKind.allCases.count - 2, "characters stay distinguishable at \(px) px")
        }
    }

    // MARK: Contact sheets (MOLIBOO_SNAPSHOT_DIR)

    func testWriteMOL03ContactSheets() throws {
        guard let dir = snapshotDir else { throw XCTSkip("Set MOLIBOO_SNAPSHOT_DIR to write MOL-03 contact sheets") }
        let all = ModulaMascotKind.allCases.sorted { $0.number < $1.number }
        try write(MOL03Sheet(title: "MOL-03 Visual Acceptance — base and Signature Cap (001–115; Legends wear their own look)", columns: 8) {
            ForEach(all, id: \.self) { k in
                MOL03Cell(kind: k, caption: "\(k.catalogueNumber) \(k.name)") {
                    HStack(spacing: 0) {
                        ModulaMascotFigure(kind: k, pose: .still(), size: 44).frame(width: 92, height: 86)
                        if k.supportsWardrobe {
                            ModulaMascotFigure(kind: k, pose: .still(), size: 44, outfit: .solo(self.cap)).frame(width: 92, height: 86)
                        } else {
                            Text("own look").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6)).frame(width: 92, height: 86)
                        }
                    }
                }
            }
        }, dir, "mol03-acceptance-base-capped.png")

        try write(MOL03Sheet(title: "MOL-03 small-scale avatars — 32 / 48 / 64 / 96 / 128 px", columns: 4) {
            ForEach(all, id: \.self) { k in
                MOL03Cell(kind: k, caption: "\(k.catalogueNumber) \(k.name)") {
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach([32, 48, 64, 96, 128], id: \.self) { px in
                            ModulaMascotFigure(kind: k, pose: .still(), size: CGFloat(px) / 2).frame(width: CGFloat(px), height: CGFloat(px) * 0.95)
                        }
                    }
                }
            }
        }, dir, "mol03-small-scale.png")

        for fam in MolibooFamily.allCases {
            try write(MOL03Sheet(title: "MOL-03 expressions — \(fam.name): " + MolibooSemanticExpression.allCases.map(\.title).joined(separator: " · "), columns: 3) {
                ForEach(fam.kinds, id: \.self) { k in
                    MOL03Cell(kind: k, caption: "\(k.catalogueNumber) \(k.name)") {
                        HStack(spacing: 0) {
                            ForEach(MolibooSemanticExpression.allCases, id: \.self) { e in
                                ModulaMascotFigure(kind: k, pose: e.stillPose, size: 26).frame(width: 54, height: 52)
                            }
                        }
                    }
                }
            }, dir, "mol03-expressions-\(fam.rawValue).png")
        }

        let reg = try XCTUnwrap(MolibooRegistryStore.bundled)
        let reactionNames = ["tap", "doubleTap", "longPress", "greeting", "equip", "signature"]
        try write(MOL03Sheet(title: "MOL-03 reactions — " + reactionNames.joined(separator: " · "), columns: 3) {
            ForEach(all, id: \.self) { k in
                let c = reg.character(key: k.rawValue)
                MOL03Cell(kind: k, caption: "\(k.catalogueNumber) \(k.name) — \(c?.signature?.line ?? "")") {
                    HStack(spacing: 0) {
                        ForEach(reactionNames, id: \.self) { n in
                            let mood = c?.reactions[n].flatMap { MolibooReactionMoods.mood(named: $0.mood) } ?? .idle
                            ModulaMascotFigure(kind: k, pose: MascotPose(t: 0.5, mood: mood, amp: 1), size: 26).frame(width: 54, height: 52)
                        }
                    }
                }
            }
        }, dir, "mol03-reactions.png")

        let difficult = Self.edgeCases.compactMap(ModulaMascotKind.init(rawValue:)) + all.filter { k in
            guard let parts = reg.character(key: k.rawValue)?.parts, k.supportsWardrobe, !Self.edgeCases.contains(k.rawValue) else { return false }
            return !Set(parts).isDisjoint(with: ["halo", "antlers", "ramHorns", "horn", "ears", "antennae", "wings", "crescent", "mushroomCap", "orbiters", "ring", "thorns", "starAntlers", "petals", "tendrils"])
        }
        try write(MOL03Sheet(title: "MOL-03 difficult fittings — base · capped still · capped t=0.7 · t=1.9 · t=3.3 (eye zones outlined)", columns: 2) {
            ForEach(difficult, id: \.self) { k in
                MOL03Cell(kind: k, caption: "\(k.catalogueNumber) \(k.name)") {
                    HStack(spacing: 0) {
                        ModulaMascotFigure(kind: k, pose: .still(), size: 40).frame(width: 82, height: 78)
                        MOL03EyeZones(kind: k, size: 40) { ModulaMascotFigure(kind: k, pose: .still(), size: 40, outfit: .solo(self.cap)) }
                        ForEach([0.7, 1.9, 3.3], id: \.self) { t in
                            ModulaMascotFigure(kind: k, pose: MascotPose(t: t, amp: 1), size: 40, outfit: .solo(self.cap)).frame(width: 82, height: 78)
                        }
                    }
                }
            }
        }, dir, "mol03-difficult-fittings.png")
    }

    private func write<V: View>(_ view: V, _ dir: URL, _ name: String) throws {
        let r = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        r.scale = 1
        let img = try XCTUnwrap(r.uiImage, name)
        try XCTUnwrap(img.pngData()).write(to: dir.appendingPathComponent(name))
    }
}

// MARK: - Measurement helpers

/// RGBA raster of a SwiftUI view rendered at 1×.
@MainActor
struct MolibooRaster {
    let width: Int, height: Int
    let px: [UInt8]

    init<V: View>(_ view: V) {
        let r = ImageRenderer(content: view)
        r.scale = 1
        let cg = r.cgImage!
        width = cg.width; height = cg.height
        var buf = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &buf, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        px = buf
    }

    func alpha(_ x: Int, _ y: Int) -> UInt8 { px[(y * width + x) * 4 + 3] }
    var opaqueCount: Int { stride(from: 3, to: px.count, by: 4).reduce(0) { $0 + (px[$1] > 128 ? 1 : 0) } }

    /// Pixels that differ visibly between two renders of the same canvas.
    func diff(_ o: MolibooRaster) -> [(Int, Int)] {
        guard o.width == width, o.height == height else { return [(0, 0)] }
        var out: [(Int, Int)] = []
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                var d = 0
                for c in 0..<4 { d = max(d, abs(Int(px[i + c]) - Int(o.px[i + c]))) }
                if d > 40 { out.append((x, y)) }
            }
        }
        return out
    }

    /// Coarse 8×8 alpha/luma signature, for "distinct at small sizes" checks.
    var fingerprint: String {
        var s = ""
        for gy in 0..<8 {
            for gx in 0..<8 {
                var a = 0, l = 0, n = 0
                for y in (gy * height / 8)..<((gy + 1) * height / 8) {
                    for x in (gx * width / 8)..<((gx + 1) * width / 8) {
                        let i = (y * width + x) * 4
                        a += Int(px[i + 3]); l += (Int(px[i]) * 3 + Int(px[i + 1]) * 6 + Int(px[i + 2])) / 10; n += 1
                    }
                }
                s += String(format: "%x%x", min(15, a / max(n, 1) / 16), min(15, l / max(n, 1) / 16))
            }
        }
        return s
    }
}

struct MolibooCapFitMeasurement: Equatable, Sendable {
    var capPixels: Int
    var attachedFraction: Double   // share of cap pixels on or within 2 px of the character's silhouette
    var eyeCover: Double           // share of the eye zones painted over by the cap
    var clipped: Bool              // cap touches the canvas edge
    var failure: String?

    static let perfect = MolibooCapFitMeasurement(capPixels: .max, attachedFraction: 1, eyeCover: 0, clipped: false, failure: nil)

    func worse(_ o: MolibooCapFitMeasurement) -> MolibooCapFitMeasurement {
        MolibooCapFitMeasurement(capPixels: min(capPixels, o.capPixels), attachedFraction: min(attachedFraction, o.attachedFraction),
                                 eyeCover: max(eyeCover, o.eyeCover), clipped: clipped || o.clipped, failure: failure ?? o.failure)
    }

    @MainActor
    static func measure(kind: ModulaMascotKind, cap: MascotWardrobeItem, pose: MascotPose, size s: CGFloat) -> MolibooCapFitMeasurement {
        let bare = MolibooRaster(ModulaMascotFigure(kind: kind, pose: pose, size: s))
        let capped = MolibooRaster(ModulaMascotFigure(kind: kind, pose: pose, size: s, outfit: .solo(cap)))
        let d = bare.diff(capped)
        let w = bare.width, h = bare.height
        var attached = 0, clipped = false
        for (x, y) in d {
            if x == 0 || y == 0 || x == w - 1 || y == h - 1 { clipped = true }
            var near = false
            for dy in -2...2 where !near {
                for dx in -2...2 {
                    let xx = x + dx, yy = y + dy
                    if xx >= 0, yy >= 0, xx < w, yy < h, bare.alpha(xx, yy) > 128 { near = true; break }
                }
            }
            if near { attached += 1 }
        }
        // Eye zones from the rig (fractions of s from the canvas centre, y down).
        let rig = MascotRig.stock(kind)
        let cx = Double(w) / 2, cy = Double(h) / 2
        let er = Double(rig.eyeSize * s) * 0.5
        var zone = 0, covered = 0
        let set = Set(d.map { $0.1 * w + $0.0 })
        for side in [-1.0, 1.0] {
            let ex = cx + side * Double(rig.eyeSpread * s), ey = cy + Double(rig.eyeY * s)
            for y in Int(ey - er)...Int(ey + er) {
                for x in Int(ex - er)...Int(ex + er) where x >= 0 && y >= 0 && x < w && y < h {
                    let dx = Double(x) - ex, dy = Double(y) - ey
                    guard dx * dx + dy * dy <= er * er else { continue }
                    zone += 1
                    if set.contains(y * w + x) { covered += 1 }
                }
            }
        }
        let frac = d.isEmpty ? 0 : Double(attached) / Double(d.count)
        let cover = zone == 0 ? 0 : Double(covered) / Double(zone)
        var m = MolibooCapFitMeasurement(capPixels: d.count, attachedFraction: frac, eyeCover: cover, clipped: clipped, failure: nil)
        let minPixels = Int(Double(s * s) * 0.04)
        if d.count < minPixels { m.failure = "cap barely visible (\(d.count) px < \(minPixels))" }
        else if clipped { m.failure = "cap clipped by the canvas edge" }
        else if frac < 0.25 { m.failure = String(format: "cap floats (only %.0f%% touches the body)", frac * 100) }
        else if cover > 0.12 { m.failure = String(format: "cap covers the eyes (%.0f%% of eye zones)", cover * 100) }
        return m
    }
}

// MARK: - Sheet views

private struct MOL03Sheet<Content: View>: View {
    let title: String
    let columns: Int
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) { content() }
        }
        .padding(12)
        .background(Color(white: 0.08))
        .fixedSize()
    }
}

private struct MOL03Cell<Content: View>: View {
    let kind: ModulaMascotKind
    let caption: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 2) {
            content()
            Text(caption).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
        }
        .padding(4)
        .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct MOL03EyeZones<Content: View>: View {
    let kind: ModulaMascotKind
    let size: CGFloat
    @ViewBuilder let content: () -> Content
    var body: some View {
        let rig = MascotRig.stock(kind)
        let c = ModulaMascotFigure.canvas(size)
        ZStack {
            content()
            ForEach([-1.0, 1.0], id: \.self) { side in
                Circle().stroke(.green.opacity(0.8), lineWidth: 0.8)
                    .frame(width: rig.eyeSize * size, height: rig.eyeSize * size)
                    .offset(x: side * rig.eyeSpread * size, y: rig.eyeY * size)
            }
            Rectangle().fill(.yellow.opacity(0.7)).frame(width: rig.hatWidth * size, height: 0.8).offset(y: rig.headTop * size)
        }
        .frame(width: c.width, height: c.height)
        .frame(width: 82, height: 78)
    }
}

extension MolibooFitProfiles {
    /// Builds the committed fit file from the live rig plus the worst measured fit per character.
    @MainActor static func export(measured: [String: MolibooCapFitMeasurement]) -> MolibooFitFile {
        var profiles: [String: MolibooFitProfile] = [:]
        for kind in ModulaMascotKind.allCases where kind.supportsWardrobe {
            var p = rigProfile(kind)
            if let m = measured[kind.rawValue] {
                func r(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
                p.measured = MolibooFitMeasured(attachedFraction: r(m.attachedFraction), eyeCover: r(m.eyeCover),
                                                phasesChecked: ["still"] + MOL03VisualAcceptanceTests.phases.map { "t=\($0)" })
                p.validated = m.failure == nil
            }
            profiles["fit/\(kind.rawValue)"] = p
        }
        return MolibooFitFile(schemaVersion: MolibooFitFile.schemaVersion, accessoryId: "cap.moliboo.signature",
                              coordinateConvention: convention, profiles: profiles)
    }
}
