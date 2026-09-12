import Foundation

struct ModuleEnvironment: Codable, Equatable, Sendable {
    var colorScheme: String
    var oled: Bool
    var accent = ModulaColor.accentHex
    var surfacePreference = "native"
    var reduceMotion: Bool
    var textScale: Double
}
