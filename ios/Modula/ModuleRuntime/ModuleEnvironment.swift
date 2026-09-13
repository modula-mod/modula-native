import Foundation

struct ModuleEnvironment: Codable, Equatable, Sendable {
    var designContractVersion = 1
    var colorScheme: String
    var theme = "system"
    var darkStyle = "standard"
    var oled: Bool
    var accent = ModulaColor.accentHex
    var fontFamily = "system"
    var density = "standard"
    var motionPersonality = "standard"
    var hapticIntensity = "standard"
    var contrastPreference = "standard"
    var transparencyPreference = "standard"
    var iconStyle = "balanced"
    var interfaceShape = "balanced"
    var moduleBranding = "blend"
    var reduceMotion: Bool
    var textScale: Double
}
