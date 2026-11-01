import Foundation

/// Internal onboarding steps. Not globally navigable URLs.
enum OnboardingStep: Int, CaseIterable, Hashable, Sendable {
    case world = 1
    case profile
    case modules
    case connections
    /// Pick your first Moliboo (endowment effect: a companion you chose is one you care about).
    case moliboo
    case control

    var number: Int { rawValue }
    static var count: Int { allCases.count }

    var progressLabel: String { "\(number) / \(Self.count)" }
    var accessibilityProgress: String { "Step \(number) of \(Self.count)" }

    var title: String {
        switch self {
        case .world: "Your digital world, your way"
        case .profile: "Your profile is your platform"
        case .modules: "Add what you need"
        case .connections: "People, content & connections"
        case .moliboo: "Pick your first Moliboo"
        case .control: "Your data. Your identity. Your rules."
        }
    }

    var headline: String {
        switch self {
        case .world: "Modula"
        case .profile: "Identity, not a page"
        case .modules: "You build the workspace"
        case .connections: "Social and modular together"
        case .moliboo: "Meet your companion"
        case .control: "You’re in control"
        }
    }

    var body: String {
        switch self {
        case .world:
            "A modular platform to connect, create and do more."
        case .profile:
            "Your profile is more than a page. Posts, modules, links, identity and tools live together."
        case .modules:
            "Modula doesn’t force one workspace. Add notes, tasks, CRM, AI, games and tools as you need them."
        case .connections:
            "People, places, perspectives and modules. Social and modular worlds coexist."
        case .moliboo:
            "Your Moliboo keeps you company across Modula. Pick one now — you can change it any time in Settings."
        case .control:
            "Privacy controls, native device security, module permissions and profile visibility stay yours. Modula does not claim cryptographic capabilities that are not implemented."
        }
    }

    var points: [(symbol: String, title: String)] {
        switch self {
        case .world:
            [("square.stack.3d.up", "Modular by design"), ("link", "Connect everything"), ("lock.shield", "You’re in control")]
        case .profile:
            [("text.bubble", "Posts"), ("shippingbox", "Modules"), ("link", "Links"), ("person.crop.circle", "Identity"), ("wrench.and.screwdriver", "Tools")]
        case .modules:
            [("note.text", "Notes"), ("checklist", "Tasks"), ("person.2", "CRM"), ("sparkles", "AI"), ("gamecontroller", "Games")]
        case .connections:
            [("person.3", "People"), ("mappin.and.ellipse", "Places"), ("eye", "Perspectives"), ("shippingbox", "Modules")]
        case .moliboo:
            []
        case .control:
            [("hand.raised", "Privacy controls"), ("faceid", "Native security"), ("switch.2", "Module permissions"), ("eye", "Profile visibility")]
        }
    }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }
}
