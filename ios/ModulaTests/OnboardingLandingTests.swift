import UIKit
import XCTest
@testable import Modula

final class OnboardingLandingTests: XCTestCase {
    func testBubblesAreUniqueAndUseRealSymbols() {
        let bubbles = OnboardingLanding.bubbles
        XCTAssertEqual(Set(bubbles.map(\.id)).count, bubbles.count)
        XCTAssertEqual(bubbles.filter { $0.content == .add }.count, 1, "Exactly one central add bubble")
        for bubble in bubbles {
            switch bubble.content {
            case .symbol(let name):
                XCTAssertNotNil(UIImage(systemName: name), "Missing SF Symbol \(name)")
            case .add, .droplet:
                break
            }
            XCTAssertTrue((0...1).contains(bubble.depth))
        }
    }

    func testModulesAppearInCluster() {
        let titles = Set(OnboardingLanding.bubbles.compactMap(\.title))
        for module in ["Vault Notes", "Tasks", "CRM", "Camera Director"] {
            XCTAssertTrue(titles.contains(module), "\(module) bubble missing")
            XCTAssertTrue(OnboardingLanding.accessibilitySummary.contains(module))
        }
        XCTAssertFalse(OnboardingLanding.accessibilitySummary.contains("Add a module"))
    }

    func testBubblesStayInsideCanvasAndDoNotCollide() {
        let canvas = OnboardingLanding.canvasSize
        let bubbles = OnboardingLanding.bubbles
        for bubble in bubbles {
            let r = bubble.diameter / 2
            XCTAssertGreaterThanOrEqual(bubble.center.x - r, -8, bubble.id)
            XCTAssertLessThanOrEqual(bubble.center.x + r, canvas.width + 8, bubble.id)
            XCTAssertGreaterThanOrEqual(bubble.center.y - r, -8, bubble.id)
            XCTAssertLessThanOrEqual(bubble.center.y + r, canvas.height + 8, bubble.id)
        }
        // Max drift is 8 pt per bubble, so keep at least 16 pt of air between rims.
        for (i, a) in bubbles.enumerated() {
            for b in bubbles[(i + 1)...] {
                let distance = hypot(a.center.x - b.center.x, a.center.y - b.center.y)
                XCTAssertGreaterThan(distance - (a.diameter + b.diameter) / 2, 8, "\(a.id) overlaps \(b.id)")
            }
        }
    }

    func testMotionIsBoundedAndParallaxFollowsDepth() {
        let near = OnboardingLanding.bubbles.first { $0.id == "add" }!
        let far = OnboardingLanding.bubbles.first { $0.id == "links" }!
        for t in stride(from: 0.0, through: 60, by: 0.5) {
            let d = OnboardingLanding.drift(for: near, at: t)
            XCTAssertLessThanOrEqual(abs(d.width), 8.01)
            XCTAssertLessThanOrEqual(abs(d.height), 8.01)
        }
        let pull = CGSize(width: 400, height: 0)
        let nearShift = OnboardingLanding.parallax(for: near, translation: pull).width
        let farShift = OnboardingLanding.parallax(for: far, translation: pull).width
        XCTAssertGreaterThan(nearShift, farShift)
        XCTAssertLessThanOrEqual(nearShift, 60, "Drag is rubber-banded")
    }
}
