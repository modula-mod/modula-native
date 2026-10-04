import SwiftUI
import UIKit
import XCTest
@testable import Modula

final class EffectKitTests: XCTestCase {
    func testAverageRGBOfSolidImage() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        let image = renderer.image { context in
            UIColor(red: 1, green: 0, blue: 0, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let cg = try XCTUnwrap(image.cgImage)
        let rgb = try XCTUnwrap(ModulaImageTint.averageRGB(cg))
        XCTAssertEqual(rgb.0, 1, accuracy: 0.05)
        XCTAssertEqual(rgb.1, 0, accuracy: 0.05)
        XCTAssertEqual(rgb.2, 0, accuracy: 0.05)
    }

    func testAdjustedColourShiftsHueAndClampsBrightness() {
        let red = Color(hue: 0, saturation: 1, brightness: 1)
        let shifted = UIColor(red.modulaAdjusted(hue: 1.0 / 3.0, brightness: 2))
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(shifted.getHue(&h, saturation: &s, brightness: &b, alpha: &a))
        XCTAssertEqual(Double(h), 1.0 / 3.0, accuracy: 0.02)
        XCTAssertLessThanOrEqual(b, 1)
    }

    func testProfileTabsAndLayoutsAreStable() {
        XCTAssertEqual(ProfileContentTab.allCases.map(\.title), ["Posts", "Modules", "Links"])
        XCTAssertEqual(ProfilePostLayout(rawValue: "grid"), .grid)
        XCTAssertEqual(ProfilePostLayout(rawValue: "list"), .list)
        XCTAssertNil(ProfilePostLayout(rawValue: "carousel"))
    }

    func testReduceMotionGate() {
        XCTAssertTrue(ModulaEffectGate.reduceMotion(true))
    }
}
