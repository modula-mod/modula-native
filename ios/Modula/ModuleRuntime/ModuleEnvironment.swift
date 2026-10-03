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
    /// Settings → Time & Units, passed to modules so they can format consistently.
    var hourCycle = ModulaPreferences.uses24HourClock ? "h23" : "h12"
    var relativeTimestamps = ModulaPreferences.relativeTimestamps
    var distanceUnit = ModulaPreferences.metricDistance ? "metric" : "imperial"
    var temperatureUnit = ModulaPreferences.celsius ? "celsius" : "fahrenheit"
}
