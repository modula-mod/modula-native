import Foundation

/// Provider availability states. Mission 02 uses a subset; later missions fill the rest.
enum IntelligenceAvailability: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case available
    case unavailable
    case unsupportedOS = "unsupported-os"
    case unsupportedDevice = "unsupported-device"
    case modelNotInstalled = "model-not-installed"
    case modelDownloading = "model-downloading"
    case disabled
    case permissionDenied = "permission-denied"
    case offline
    case temporarilyUnavailable = "temporarily-unavailable"

    var isEligibleForRouting: Bool { self == .available }

    var displayName: String {
        switch self {
        case .available: "Available"
        case .unavailable: "Unavailable"
        case .unsupportedOS: "Unsupported OS"
        case .unsupportedDevice: "Device not eligible"
        case .modelNotInstalled: "Model not installed"
        case .modelDownloading: "Model downloading"
        case .disabled: "Disabled"
        case .permissionDenied: "Permission denied"
        case .offline: "Offline"
        case .temporarilyUnavailable: "Temporarily unavailable"
        }
    }
}
