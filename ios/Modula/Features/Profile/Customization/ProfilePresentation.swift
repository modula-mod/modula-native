import SwiftUI

/// Public Profile identity styling. Distinct from `AppearanceStore` (viewer chrome).
struct ProfilePresentation: Hashable, Sendable, Equatable {
    var accent: ProfileAccent?
    var featuredModuleIDs: [String]
    var featuredLinkIDs: [String]

    static let unspecified = ProfilePresentation(accent: nil, featuredModuleIDs: [], featuredLinkIDs: [])
}

enum ProfileAccent: String, Hashable, Sendable, CaseIterable, Identifiable {
    case teal, ocean, violet, coral, moss, graphite

    var id: Self { self }

    var title: String {
        switch self {
        case .teal: "Teal"
        case .ocean: "Ocean"
        case .violet: "Violet"
        case .coral: "Coral"
        case .moss: "Moss"
        case .graphite: "Graphite"
        }
    }

    var hex: String {
        switch self {
        case .teal: "#369CAA"
        case .ocean: "#3478F6"
        case .violet: "#7656D6"
        case .coral: "#D66056"
        case .moss: "#4E8B67"
        case .graphite: "#667085"
        }
    }

    var color: Color { Color(hex: hex) }

    init?(parsing raw: String?) {
        guard let raw else { return nil }
        let key = raw.lowercased().replacingOccurrences(of: "modula", with: "")
        if let match = Self.allCases.first(where: { $0.rawValue == key || $0.hex.lowercased() == raw.lowercased() }) {
            self = match
            return
        }
        switch key {
        case "modulteal", "teal", "modulateal": self = .teal
        default: return nil
        }
    }
}

struct CoverFocalPoint: Hashable, Sendable {
    var x: Double
    var y: Double

    static let center = CoverFocalPoint(x: 0.5, y: 0.5)

    var unitPoint: UnitPoint { UnitPoint(x: x, y: y) }
}

struct ProfileCustomizationCapabilities: Sendable, Equatable {
    var headlineWritable = false
    var languagesWritable = false
    var linksWritable = false
    var featuredModulesWritable = false
    var presentationWritable = false
    var accentWritable = false
    var coverFocalWritable = false
    var avatarWritable = false
    var coverWritable = false

    static let production = ProfileCustomizationCapabilities()
}

private struct ProfileAccentColorKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    var profileAccentColor: Color? {
        get { self[ProfileAccentColorKey.self] }
        set { self[ProfileAccentColorKey.self] = newValue }
    }
}

enum ProfileFieldPrivacy {
    /// Never surface these even if an authenticated payload includes them.
    static let blockedKeys: Set<String> = ["email", "phone", "birthday", "birthDate", "privateLocation"]

    static func isPublic(_ visibility: ProfileVisibility?) -> Bool {
        visibility == nil || visibility == .public
    }
}

extension ProfilePresentation {
    static func decode(from value: JSONValue?) -> ProfilePresentation {
        guard let value else { return .unspecified }
        let accent = ProfileAccent(parsing: value["accent"]?.string ?? value["profileAccent"]?.string)
        let modules = (value["featuredModuleIds"]?.array ?? []).compactMap(\.string)
        let links = (value["featuredLinkIds"]?.array ?? []).compactMap(\.string)
        return ProfilePresentation(accent: accent, featuredModuleIDs: modules, featuredLinkIDs: links)
    }
}
