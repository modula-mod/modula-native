import Foundation

/// Signed-out onboarding steps (after the landing). Not globally navigable URLs.
/// The notification primer is skipped when it isn't offerable (see `OnboardingView`).
enum OnboardingStep: Int, CaseIterable, Hashable, Sendable {
    /// What Modula is, in one breath.
    case intro = 1
    /// Name and age range ("Let's get to know you").
    case you
    /// Where did you hear about us?
    case source
    /// Pick your first Moliboo (endowment effect: a companion you chose is one you care about).
    case moliboo
    /// Notification primer with a mock lock screen. Never on launch.
    case notifications
    /// Create an account or sign in.
    case finale

    var number: Int { rawValue }
    static var count: Int { allCases.count }

    var progressLabel: String { "\(number) / \(Self.count)" }
    var accessibilityProgress: String { "Step \(number) of \(Self.count)" }

    var title: String {
        switch self {
        case .intro: "Your digital world, your way"
        case .you: "Let’s get to know you"
        case .source: "Where did you hear about us?"
        case .moliboo: "Pick your first Moliboo"
        case .notifications: "Stay in the loop"
        case .finale: "You’re all set"
        }
    }

    var body: String {
        switch self {
        case .intro: "One app built from modules: people, notes, tasks, music and more. Add only what you need."
        case .you: "Just the basics. It stays on this device until you create your account."
        case .source: "Pick one. It helps us reach more people like you."
        case .moliboo: "Your Moliboo keeps you company across Modula. You can change it any time in Settings."
        case .notifications: "Don’t miss out on what your friends are up to."
        case .finale: "Create your account to save your world, or sign in if you already have one."
        }
    }

    var points: [(symbol: String, title: String)] {
        switch self {
        case .intro:
            [("square.stack.3d.up", "Modular by design"), ("person.2", "Social and productive"), ("lock.shield", "You’re in control")]
        default:
            []
        }
    }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }
}

/// Answers collected during onboarding. There is no backend route for them yet, so
/// they stay on this device (UserDefaults). The name pre-fills Create Account.
struct OnboardingAnswers: Codable, Equatable, Sendable {
    var name: String?
    var ageRange: String?
    var source: String?

    static let ageRanges = ["Under 18", "18–24", "25–34", "35–44", "45–54", "55+"]
    /// SF Symbols stand in for brand marks (no licensed brand assets ship in the app).
    static let sources: [(title: String, symbol: String)] = [
        ("TikTok", "music.note"),
        ("Instagram", "camera"),
        ("Facebook", "person.2.wave.2"),
        ("YouTube", "play.rectangle"),
        ("Snapchat", "bolt.heart"),
        ("App Store", "apple.logo"),
        ("From a friend", "person.line.dotted.person"),
        ("Other", "ellipsis"),
    ]

    private static let key = "onboarding.answers.v1"

    static func load(_ defaults: UserDefaults = .standard) -> OnboardingAnswers {
        guard let data = defaults.data(forKey: key),
              let answers = try? JSONDecoder().decode(OnboardingAnswers.self, from: data) else { return OnboardingAnswers() }
        return answers
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}
