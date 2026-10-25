import XCTest
import SwiftUI
@testable import Modula

/// Art review tool: renders every 2D Moliboo (bare and with a hat) into one contact sheet per family.
/// Skipped unless `MOLIBOO_SNAPSHOT_DIR` is set (pass `TEST_RUNNER_MOLIBOO_SNAPSHOT_DIR=/path` to xcodebuild).
@MainActor
final class MolibooArtSnapshotTests: XCTestCase {
    func testRenderFamilyContactSheets() throws {
        guard let dir = ProcessInfo.processInfo.environment["MOLIBOO_SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("Set MOLIBOO_SNAPSHOT_DIR to render Moliboo contact sheets")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let hat = MascotWardrobeCatalog.all.first { $0.slot == .hat }
        for fam in MolibooFamily.allCases {
            let kinds = ModulaMascotKind.allCases.filter { $0.family == fam }.sorted { $0.number < $1.number }
            let sheet = MolibooContactSheet(kinds: kinds, hat: hat).environment(\.colorScheme, .dark)
            let r = ImageRenderer(content: sheet)
            r.scale = 1
            let img = try XCTUnwrap(r.uiImage, fam.rawValue)
            try XCTUnwrap(img.pngData()).write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(fam.rawValue).png"))
        }
    }
}

/// Home and Studio resolve the same equipped outfit; Home's portrait draws it; Legends stay undressed;
/// no Moliboo is clipped by the figure's own draw canvas.
@MainActor
final class MolibooOutfitSyncTests: XCTestCase {
    func testHomeAndStudioResolveSameOutfit() throws {
        let store = MascotWardrobeStore.shared
        // Wardrobe edits are (correctly) ignored while a Legend is the selected Moliboo, so pin a wardrobe-capable
        // selection for the test and restore the simulator's own selection and outfit afterwards.
        let d = UserDefaults.standard
        let previousKind = d.string(forKey: ModulaMascotSettings.kindKey)
        d.set(ModulaMascotKind.pip.rawValue, forKey: ModulaMascotSettings.kindKey)
        let previous = store.outfit
        defer {
            store.apply(previous)   // simulator test store only; restores whatever was there
            if let previousKind { d.set(previousKind, forKey: ModulaMascotSettings.kindKey) } else { d.removeObject(forKey: ModulaMascotSettings.kindKey) }
        }
        let hat = try XCTUnwrap(MascotWardrobeCatalog.all.first { $0.slot == .hat && $0.unlock == .free && store.canEquip($0) })
        store.apply(.empty)
        let bare = try XCTUnwrap(MolibooPortrait.image(for: "pip")?.pngData())
        store.equip(hat)
        XCTAssertFalse(store.outfit.isEmpty)
        for kind: ModulaMascotKind in [.pebble, .pip, .flick] {
            XCTAssertEqual(MolibooOutfit.equipped(for: kind), store.outfit, "Home and Studio share one outfit for \(kind)")
        }
        let dressed = try XCTUnwrap(MolibooPortrait.image(for: "pip")?.pngData())
        XCTAssertNotEqual(dressed, bare, "Home portrait must render the equipped outfit")
        if let legend = ModulaMascotKind.allCases.first(where: { !$0.family.supportsWardrobe }) {
            XCTAssertEqual(MolibooOutfit.equipped(for: legend), .empty, "Legends stay undressed")
        }
    }

    func testFiguresFitInsideTheirDrawCanvas() throws {
        var clipped: [String] = []
        for k in ModulaMascotKind.allCases {
            let s: CGFloat = 100, c = ModulaMascotFigure.canvas(s)
            let r = ImageRenderer(content: ModulaMascotFigure(kind: k, pose: .still(), size: s)
                .frame(width: c.width * ModulaMascotFigure.drawOverscan, height: c.height))
            r.scale = 1
            let img = try XCTUnwrap(r.cgImage, k.rawValue)
            let w = img.width, h = img.height
            var a = [UInt8](repeating: 0, count: w * h)
            let ctx = try XCTUnwrap(CGContext(data: &a, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue))
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            let edge = (0..<h).contains { y in a[y * w] > 8 || a[y * w + w - 1] > 8 }
            if edge { clipped.append(k.rawValue) }
        }
        XCTAssertEqual(clipped, [], "Figures drawn past the canvas edge (clipped): \(clipped)")
    }
}

private struct MolibooContactSheet: View {
    let kinds: [ModulaMascotKind]
    let hat: MascotWardrobeItem?
    var body: some View {
        let cols = Array(repeating: GridItem(.fixed(220), spacing: 8), count: 5)
        LazyVGrid(columns: cols, spacing: 8) {
            ForEach(kinds, id: \.self) { k in
                VStack(spacing: 2) {
                    HStack(spacing: 0) {
                        ModulaMascotFigure(kind: k, pose: .still(), size: 52).frame(width: 108, height: 100)
                        ModulaMascotFigure(kind: k, pose: .still(), size: 52, outfit: hat.map { MascotOutfit.solo($0) } ?? .empty)
                            .frame(width: 108, height: 100)
                    }
                    Text(String(format: "%03d %@", k.number, k.name)).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                }
                .frame(width: 220, height: 126)
                .background(Color(white: 0.16))
            }
        }
        .padding(8)
        .frame(width: 5 * 220 + 4 * 8 + 16)
        .background(Color(white: 0.08))
    }
}
