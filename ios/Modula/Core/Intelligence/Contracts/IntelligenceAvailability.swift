import Foundation

/// Provider availability states. Mission 02 uses a subset; later missions fill the rest.
enum IntelligenceAvailability: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case available
    case unavailable
    case unsupportedDevice = "unsupported-device"
    case modelNotInstalled = "model-not-installed"
    case modelDownloading = "model-downloading"
    case disabled
    case permissionDenied = "permission-denied"
    case offline
    case temporarilyUnavailable = "temporarily-unavailable"

    var isEligibleForRouting: Bool { self == .available }
}
