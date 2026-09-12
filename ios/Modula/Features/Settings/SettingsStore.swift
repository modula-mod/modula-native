import SwiftUI
import Observation

@MainActor @Observable
final class SettingsStore {
    enum Appearance: String, CaseIterable, Codable { case system, light, dark, oled }
    private let defaults: UserDefaults
    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: "modula.native.appearance.v1") }
    }
    var colorScheme: ColorScheme? {
        switch appearance {
        case .system: nil
        case .light: .light
        case .dark, .oled: .dark
        }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = Appearance(rawValue: defaults.string(forKey: "modula.native.appearance.v1") ?? "") ?? .system
    }
}
