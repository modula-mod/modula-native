import Foundation

enum FirstRunStep: Int, CaseIterable, Hashable, Sendable {
    case profile
    case modules
    case notifications

    var title: String {
        switch self {
        case .profile: "Your profile"
        case .modules: "Starter modules"
        case .notifications: "Stay in the loop"
        }
    }

    var body: String {
        switch self {
        case .profile:
            "Choose how you appear. Email stays private and is never shown on your profile."
        case .modules:
            "Install only real Product Hub modules. Nothing is added for decoration."
        case .notifications:
            "Modula can notify you about people and modules. Permission is requested only after this explanation."
        }
    }
}

/// Interests are omitted: Greenfield has no verified interest/topic storage in this checkout.
enum FirstRunCapabilities: Equatable, Sendable {
    static let interestsAvailable = false
    static let accountFirstRunContract = false
}
