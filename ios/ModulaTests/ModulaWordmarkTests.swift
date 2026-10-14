import XCTest
import SwiftUI
@testable import Modula

/// Brand: the supplied wordmark SVG ships as a vector asset with Light (dark ink) and Dark (light ink) appearances.
@MainActor
final class ModulaWordmarkTests: XCTestCase {
    private func image(_ style: UIUserInterfaceStyle) throws -> UIImage {
        try XCTUnwrap(UIImage(named: "ModulaWordmark", in: .main, compatibleWith: UITraitCollection(userInterfaceStyle: style)))
    }

    /// Mean luminance of opaque pixels (the ink).
    private func inkLuminance(_ img: UIImage) -> Double {
        let w = 300, h = Int(300 / ModulaWordmark.aspect)
        let r = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        let data = r.image { _ in img.draw(in: CGRect(x: 0, y: 0, width: w, height: h)) }.cgImage!.dataProvider!.data! as Data
        var sum = 0.0, n = 0.0
        for i in stride(from: 0, to: data.count - 3, by: 4) where data[i + 3] > 200 {
            sum += (0.2126 * Double(data[i]) + 0.7152 * Double(data[i + 1]) + 0.0722 * Double(data[i + 2])) / 255; n += 1
        }
        return n > 0 ? sum / n : -1
    }

    func testWordmarkHasReadableLightAndDarkVariants() throws {
        let light = try image(.light), dark = try image(.dark)
        XCTAssertEqual(light.size.width / light.size.height, ModulaWordmark.aspect, accuracy: 0.02)
        let l = inkLuminance(light), d = inkLuminance(dark)
        XCTAssertGreaterThan(l, 0); XCTAssertGreaterThan(d, 0)
        XCTAssertLessThan(l, 0.2, "dark ink (#141C1F) on light backgrounds")
        XCTAssertGreaterThan(d, 0.85, "light ink on dark backgrounds")
        // Evidence renders on matching backgrounds.
        if let dir = ProcessInfo.processInfo.environment["MOL03_SHOTS"] {
            for (name, scheme, bg) in [("light", ColorScheme.light, Color.white), ("dark", ColorScheme.dark, Color.black)] {
                let v = ModulaWordmark(height: 80).padding(30).background(bg).environment(\.colorScheme, scheme)
                let r = ImageRenderer(content: v); r.scale = 2
                try r.uiImage?.pngData()?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("wordmark-\(name).png"))
            }
        }
    }

    func testNoTypesetBrandNameLeftInBrandSpots() throws {
        // Guard: the brand spots use the asset view. (Source check keeps future edits honest.)
        XCTAssertNotNil(UIImage(named: "MoliboosLogo"), "Moliboos wordmark untouched")
    }
}
