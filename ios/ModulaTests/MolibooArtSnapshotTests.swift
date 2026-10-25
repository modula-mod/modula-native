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

/// Wide Moliboos (wings, tails, props) must never be clipped: neither by the figure canvas nor by the fitted
/// portrait / thumbnail images used on Home, cards and pickers. Also checks the canonical numbering.
@MainActor
final class MolibooFigureBoundsTests: XCTestCase {
    private func touchesEdge(_ img: CGImage) -> Bool {
        guard let b = MolibooPortrait.alphaBounds(img) else { return false }
        return b.minX <= 0 || b.minY <= 0 || b.maxX >= CGFloat(img.width) || b.maxY >= CGFloat(img.height)
    }

    func testFiguresFitInsideCanvas() throws {
        var clipped: [String] = []
        for k in ModulaMascotKind.allCases {
            let s: CGFloat = 100, c = ModulaMascotFigure.canvas(s)
            let r = ImageRenderer(content: ModulaMascotFigure(kind: k, pose: .still(), size: s).frame(width: c.width * ModulaMascotFigure.drawOverscan, height: c.height))
            r.scale = 1
            let img = try XCTUnwrap(r.cgImage, k.rawValue)
            if touchesEdge(img) { clipped.append(k.rawValue) }
        }
        XCTAssertEqual(clipped, [], "Figures drawn past the canvas edge (clipped): \(clipped)")
    }

    func testFittedPortraitsAndThumbsNeverClip() throws {
        var clipped: [String] = []
        for k in ModulaMascotKind.allCases {
            for size: CGFloat in [64, 180] {
                let img = try XCTUnwrap(MolibooPortrait.renderFitted(k, pointSize: size, scale: 1)?.cgImage, k.rawValue)
                XCTAssertGreaterThanOrEqual(CGFloat(img.width), size * MolibooPortrait.nominalFrame - 1)
                if touchesEdge(img) { clipped.append("\(k.rawValue)@\(Int(size))") }
            }
        }
        XCTAssertEqual(clipped, [], "Portraits clipped at their edges: \(clipped)")
    }

    /// Home (portrait / stage) and Studio resolve the same equipped outfit, and Home's portrait actually draws it.
    /// Uses a free item on the simulator's store and restores the previous outfit afterwards.
    func testHomeAndStudioResolveSameOutfit() throws {
        let store = MascotWardrobeStore.shared
        let previous = store.outfit
        defer { store.apply(previous) }
        let hat = try XCTUnwrap(MascotWardrobeCatalog.all.first { $0.slot == .hat && $0.unlock == .free && store.canEquip($0) })
        store.equip(hat)
        for kind: ModulaMascotKind in [.pebble, .pip, .flick] {
            XCTAssertEqual(MolibooOutfit.equipped(for: kind), store.outfit, "Home and Studio share one outfit for \(kind)")
        }
        let dressed = try XCTUnwrap(MolibooPortrait.image(for: "pip")?.pngData())
        let bare = try XCTUnwrap(MolibooPortrait.renderFitted(.pip, pointSize: 180, scale: 2)?.pngData())
        XCTAssertNotEqual(dressed, bare, "Home portrait must render the equipped outfit")
        let studioMatch = try XCTUnwrap(MolibooPortrait.renderFitted(.pip, pointSize: 180, scale: 2, outfit: store.outfit)?.pngData())
        XCTAssertEqual(dressed, studioMatch, "Home portrait equals the figure in Studio's outfit")
    }

    func testCanonicalNumbersAndFamilies() {
        XCTAssertEqual(ModulaMascotKind.flick.number > 1, true)
        XCTAssertEqual(ModulaMascotKind.flick.family, .underground)
        let numbers = ModulaMascotKind.allCases.map(\.number)
        XCTAssertEqual(Set(numbers).count, numbers.count, "Every Moliboo has a unique canonical number")
        XCTAssertFalse(numbers.contains(999), "Every Moliboo has a profile number")
        for k in ModulaMascotKind.allCases { XCTAssertTrue(k.family.range.contains(k.number), k.rawValue) }
        XCTAssertEqual(MolibooFamily.underground.displayTitle, "The Underground")
        XCTAssertEqual(MolibooFamily.originals.displayTitle, "The Originals")
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
