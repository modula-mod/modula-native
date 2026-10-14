import XCTest
import SwiftUI
@testable import Modula

final class MOL03AmbienceTests: XCTestCase {
    private func at(_ hour: Int) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 10; c.day = 14; c.hour = hour
        return Calendar.current.date(from: c)!
    }

    func testTimeOfDayBands() {
        XCTAssertEqual(MolibooAmbience.current(at(4)), .night)
        XCTAssertEqual(MolibooAmbience.current(at(5)), .morning)
        XCTAssertEqual(MolibooAmbience.current(at(11)), .morning)
        XCTAssertEqual(MolibooAmbience.current(at(12)), .afternoon)
        XCTAssertEqual(MolibooAmbience.current(at(17)), .evening)
        XCTAssertEqual(MolibooAmbience.current(at(21)), .night)
        XCTAssertEqual(MolibooAmbience.current(at(23)), .night)
    }

    func testEveryMoodHasASkyAndDarkFlag() {
        for a in MolibooAmbience.allCases { XCTAssertGreaterThanOrEqual(a.sky.count, 2, a.rawValue) }
        XCTAssertTrue(MolibooAmbience.night.isDark)
        XCTAssertFalse(MolibooAmbience.morning.isDark)
    }

    /// The painter is pure and renders every mood (also at a frozen, Reduce-Motion time) without trapping.
    @MainActor
    func testPainterRendersEveryMood() {
        for a in MolibooAmbience.allCases {
            for t in [0.0, 12.5, 3600.3] {
                let r = ImageRenderer(content: Canvas { g, size in MolibooAmbientPainter(size: size, t: t).draw(a, in: &g) }.frame(width: 120, height: 200))
                XCTAssertNotNil(r.uiImage, "\(a) t=\(t)")
            }
        }
    }
}
