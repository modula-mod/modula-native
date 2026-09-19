import Foundation
import LocalAuthentication

enum AppLockInterval: String, CaseIterable, Codable, Hashable, Sendable {
    case immediately
    case oneMinute
    case fiveMinutes
    case fifteenMinutes
    case oneHour

    var title: String {
        switch self {
        case .immediately: "Immediately"
        case .oneMinute: "After 1 minute"
        case .fiveMinutes: "After 5 minutes"
        case .fifteenMinutes: "After 15 minutes"
        case .oneHour: "After 1 hour"
        }
    }

    var duration: Duration {
        switch self {
        case .immediately: .seconds(0)
        case .oneMinute: .seconds(60)
        case .fiveMinutes: .seconds(300)
        case .fifteenMinutes: .seconds(900)
        case .oneHour: .seconds(3600)
        }
    }
}

enum BiometricKind: Equatable, Sendable {
    case faceID
    case touchID
    case opticID
    case none

    var title: String {
        switch self {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        case .none: "Biometrics"
        }
    }

    var unlockLabel: String {
        switch self {
        case .faceID: "Unlock with Face ID"
        case .touchID: "Unlock with Touch ID"
        case .opticID: "Unlock with Optic ID"
        case .none: "Unlock with biometrics"
        }
    }

    var systemImage: String {
        switch self {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        case .none: "lock.fill"
        }
    }
}

enum BiometricAvailability: Equatable, Sendable {
    case available(BiometricKind)
    case notEnrolled(BiometricKind)
    case lockedOut(BiometricKind)
    case unavailable

    var kind: BiometricKind {
        switch self {
        case .available(let kind), .notEnrolled(let kind), .lockedOut(let kind): kind
        case .unavailable: .none
        }
    }

    var isUsable: Bool {
        if case .available = self { return true }
        return false
    }

    var explanation: String {
        switch self {
        case .available(let kind): "\(kind.title) is available on this device."
        case .notEnrolled(let kind): "\(kind.title) is supported but not enrolled."
        case .lockedOut(let kind): "\(kind.title) is locked out. Use your Modula passcode."
        case .unavailable: "Biometrics are not available on this device."
        }
    }
}

enum BiometricAuthResult: Equatable, Sendable {
    case success
    case failed
    case cancelled
    case unavailable
}

protocol BiometricAuthenticating: Sendable {
    func availability() -> BiometricAvailability
    func authenticate(reason: String) async -> BiometricAuthResult
}

protocol AppLockCredentialStoring: Sendable {
    func hasPasscode() throws -> Bool
    func setPasscode(_ passcode: String) throws
    func verifyPasscode(_ passcode: String) throws -> Bool
    func clear() throws
}

struct AppLockSettings: Codable, Equatable, Sendable {
    var enabled: Bool
    var interval: AppLockInterval
    var biometricsEnabled: Bool
    var hideInAppSwitcher: Bool

    static let `default` = AppLockSettings(
        enabled: false,
        interval: .immediately,
        biometricsEnabled: true,
        hideInAppSwitcher: true
    )
}

enum AppLockAttemptPolicy {
    static func delay(afterFailureCount count: Int) -> Duration {
        switch count {
        case ...4: .seconds(0)
        case 5...7: .seconds(5)
        case 8...10: .seconds(30)
        default: .seconds(60)
        }
    }
}
