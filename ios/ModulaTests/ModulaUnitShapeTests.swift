import SwiftUI
import XCTest
@testable import Modula

/// The Modula Unit path: closed, 4-fold symmetric, hole cut under both fill rules, tight bounds.
final class ModulaUnitShapeTests: XCTestCase {
    private let rect = CGRect(x: 0, y: 0, width: 600, height: 600)
    private var path: Path { ModulaUnitShape().path(in: rect) }

    func testPathIsClosedTwoSubpaths() {
        var moves = 0, closes = 0
        var subpathStart: CGPoint?
        var current: CGPoint?
        var gaps: [CGFloat] = []
        path.forEach { element in
            switch element {
            case .move(let p):
                moves += 1; subpathStart = p; current = p
            case .line(let p): current = p
            case .quadCurve(let p, _): current = p
            case .curve(let p, _, _): current = p
            case .closeSubpath:
                closes += 1
                if let s = subpathStart, let c = current { gaps.append(hypot(s.x - c.x, s.y - c.y)) }
            }
        }
        XCTAssertEqual(moves, 2, "outer contour + hole")
        XCTAssertEqual(closes, 2)
        // Each subpath already ends where it started (close adds no visible segment).
        for gap in gaps { XCTAssertLessThan(gap, 0.01) }
    }

    func testBoundsAreTheUnitBox() {
        let b = path.boundingRect
        XCTAssertEqual(b.minX, 0, accuracy: 0.05); XCTAssertEqual(b.minY, 0, accuracy: 0.05)
        XCTAssertEqual(b.maxX, 600, accuracy: 0.05); XCTAssertEqual(b.maxY, 600, accuracy: 0.05)
    }

    func testFourFoldAndMirrorSymmetry() {
        let p = path, n = 61
        var mismatches = 0, inside = 0
        var notes: [String] = []
        for i in 0..<n { for j in 0..<n {
            let x = (CGFloat(i) + 0.5) / CGFloat(n) * 600 - 300, y = (CGFloat(j) + 0.5) / CGFloat(n) * 600 - 300
            let at: (CGFloat, CGFloat) -> Bool = { p.contains(CGPoint(x: 300 + $0, y: 300 + $1), eoFill: true) }
            let v = at(x, y)
            if v { inside += 1 }
            for reflected in [(-y, x), (-x, -y), (y, -x), (-x, y), (x, -y), (y, x)] {
                let other = at(reflected.0, reflected.1)
                if other != v {
                    mismatches += 1
                    if notes.count < 8 {
                        notes.append(String(
                            format: "(%.1f,%.1f)=%d reflect(%.1f,%.1f)=%d",
                            Double(x), Double(y), v ? 1 : 0,
                            Double(reflected.0), Double(reflected.1), other ? 1 : 0
                        ))
                    }
                }
            }
        }}
        XCTAssertEqual(mismatches, 0, notes.joined(separator: " | "))
        XCTAssertGreaterThan(inside, n * n / 3)
    }

    func testConstructionPoints() {
        let p = path
        let s: CGFloat = 600
        func at(_ x: CGFloat, _ y: CGFloat, eo: Bool = true) -> Bool { p.contains(CGPoint(x: x * s, y: y * s), eoFill: eo) }
        // Centre hole — under both fill rules.
        XCTAssertFalse(at(0.5, 0.5)); XCTAssertFalse(at(0.5, 0.5, eo: false))
        XCTAssertFalse(at(0.5 + 0.14, 0.5))
        XCTAssertTrue(at(0.5 + 0.16, 0.5))
        // Lobe centres are solid.
        let d = ModulaUnitShape.lobeOffset
        XCTAssertTrue(at(0.5 + d, 0.5 + d)); XCTAssertTrue(at(0.5 - d, 0.5 - d, eo: false))
        // Concave side: deepest point is 0.1818 in from the edge.
        XCTAssertFalse(at(0.5, 0.17)); XCTAssertTrue(at(0.5, 0.19))
        // Geometry constants match brand/modula-unit-geometry.md.
        XCTAssertEqual(ModulaUnitShape.connectionOffset, 0.501509, accuracy: 1e-5)
        XCTAssertEqual(ModulaUnitShape.tangentAngle, 30.2726, accuracy: 1e-3)
    }
}
