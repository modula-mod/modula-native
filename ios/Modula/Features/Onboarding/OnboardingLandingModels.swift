import CoreGraphics
import Foundation

/// Content of the signed-out landing screen: a floating cluster of glass bubbles,
/// each one a real part of Modula (its modules and shell surfaces).
///
/// Layout is authored on a 390 × 460 pt design canvas and scaled to fit, so the
/// cluster keeps its composition on every iPhone and at every text size.
enum OnboardingLanding {
    static let headline = "A new kind of app, built from modules that get things done"
    static let continueTitle = "Let’s go"
    static let canvasSize = CGSize(width: 390, height: 460)

    enum Content: Hashable, Sendable {
        /// SF Symbol on a tinted sphere.
        case symbol(String)
        /// The central "add a module" bubble.
        case add
        /// Empty glass droplet for depth.
        case droplet
    }

    struct Bubble: Identifiable, Hashable, Sendable {
        let id: String
        /// VoiceOver name. `nil` for decorative droplets.
        let title: String?
        let content: Content
        /// Hex tint of the inner sphere.
        let tint: String
        /// Centre on the design canvas.
        let center: CGPoint
        let diameter: CGFloat
        /// 0 (far) … 1 (near). Drives drift amplitude, drag parallax and shadow.
        let depth: CGFloat
        /// Phase offset so bubbles never drift in lockstep.
        let phase: Double

        var isDecorative: Bool { title == nil }
    }

    static let bubbles: [Bubble] = [
        Bubble(id: "add", title: "Add a module", content: .add, tint: "#369CAA", center: CGPoint(x: 195, y: 338), diameter: 108, depth: 1.0, phase: 0),
        Bubble(id: "vault-notes", title: "Vault Notes", content: .symbol("note.text"), tint: "#369CAA", center: CGPoint(x: 100, y: 238), diameter: 94, depth: 0.85, phase: 1.1),
        Bubble(id: "tasks", title: "Tasks", content: .symbol("checklist"), tint: "#30B26B", center: CGPoint(x: 292, y: 244), diameter: 88, depth: 0.8, phase: 2.3),
        Bubble(id: "nodus", title: "Nodus intelligence", content: .symbol("sparkles"), tint: "#9B6BFF", center: CGPoint(x: 198, y: 172), diameter: 72, depth: 0.6, phase: 3.7),
        Bubble(id: "crm", title: "CRM", content: .symbol("person.2.fill"), tint: "#4F6BFF", center: CGPoint(x: 74, y: 118), diameter: 80, depth: 0.55, phase: 4.4),
        Bubble(id: "camera-director", title: "Camera Director", content: .symbol("camera.aperture"), tint: "#F28A2E", center: CGPoint(x: 306, y: 112), diameter: 92, depth: 0.7, phase: 5.2),
        Bubble(id: "profile", title: "Profile", content: .symbol("person.crop.circle.fill"), tint: "#3FBFA8", center: CGPoint(x: 190, y: 64), diameter: 64, depth: 0.4, phase: 0.6),
        Bubble(id: "messages", title: "Messages", content: .symbol("bubble.left.and.bubble.right.fill"), tint: "#2F8CFF", center: CGPoint(x: 60, y: 338), diameter: 64, depth: 0.65, phase: 2.9),
        Bubble(id: "games", title: "Games", content: .symbol("gamecontroller.fill"), tint: "#F04A6A", center: CGPoint(x: 330, y: 350), diameter: 62, depth: 0.6, phase: 4.9),
        Bubble(id: "places", title: "Places", content: .symbol("mappin.and.ellipse"), tint: "#E9B526", center: CGPoint(x: 92, y: 30), diameter: 46, depth: 0.3, phase: 1.8),
        Bubble(id: "links", title: "Links", content: .symbol("link"), tint: "#2FB7C9", center: CGPoint(x: 300, y: 22), diameter: 44, depth: 0.3, phase: 3.3),
        Bubble(id: "drop-1", title: nil, content: .droplet, tint: "#FFFFFF", center: CGPoint(x: 148, y: 118), diameter: 22, depth: 0.25, phase: 0.9),
        Bubble(id: "drop-2", title: nil, content: .droplet, tint: "#FFFFFF", center: CGPoint(x: 252, y: 176), diameter: 18, depth: 0.2, phase: 2.1),
        Bubble(id: "drop-3", title: nil, content: .droplet, tint: "#FFFFFF", center: CGPoint(x: 28, y: 216), diameter: 26, depth: 0.35, phase: 3.9),
        Bubble(id: "drop-4", title: nil, content: .droplet, tint: "#FFFFFF", center: CGPoint(x: 358, y: 210), diameter: 20, depth: 0.3, phase: 5.6),
        Bubble(id: "drop-5", title: nil, content: .droplet, tint: "#FFFFFF", center: CGPoint(x: 128, y: 418), diameter: 18, depth: 0.45, phase: 4.2),
        Bubble(id: "drop-6", title: nil, content: .droplet, tint: "#FFFFFF", center: CGPoint(x: 272, y: 430), diameter: 14, depth: 0.4, phase: 1.4),
    ]

    /// Spoken summary of the cluster (it is one accessibility element).
    static var accessibilitySummary: String {
        let names = bubbles.filter { !$0.isDecorative && $0.content != .add }.compactMap(\.title)
        return "Modula modules: " + names.joined(separator: ", ")
    }

    /// Gentle drift for a bubble at time `t` (seconds). Amplitude grows with depth.
    static func drift(for bubble: Bubble, at t: Double) -> CGSize {
        let amplitude = 3 + 5 * Double(bubble.depth)
        let speed = 0.32 + 0.12 * Double(1 - bubble.depth)
        return CGSize(
            width: amplitude * 0.7 * sin(t * speed * 0.8 + bubble.phase * 1.7),
            height: amplitude * sin(t * speed + bubble.phase)
        )
    }

    /// Drag parallax: nearer bubbles follow the finger more. Rubber-banded.
    static func parallax(for bubble: Bubble, translation: CGSize) -> CGSize {
        func band(_ value: CGFloat) -> CGFloat {
            let limit: CGFloat = 60
            return limit * tanh(value / (limit * 2.2))
        }
        let factor = 0.35 + 0.65 * bubble.depth
        return CGSize(width: band(translation.width) * factor, height: band(translation.height) * factor)
    }
}
