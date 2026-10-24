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
