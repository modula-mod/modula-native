import Foundation
import LocalAuthentication

struct SystemBiometricAuthService: BiometricAuthenticating {
    func availability() -> BiometricAvailability {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let kind = kind(from: context.biometryType)
        if canEvaluate {
            return .available(kind)
        }
        if let code = error?.code {
            if code == LAError.biometryNotEnrolled.rawValue {
                return .notEnrolled(kind == .none ? .faceID : kind)
            }
            if code == LAError.biometryLockout.rawValue {
                return .lockedOut(kind == .none ? .faceID : kind)
            }
        }
        return .unavailable
    }

    func authenticate(reason: String) async -> BiometricAuthResult {
        let context = LAContext()
        context.localizedFallbackTitle = "Enter Passcode"
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            return success ? .success : .failed
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel, .userFallback:
                return .cancelled
            case .biometryNotAvailable, .biometryNotEnrolled:
                return .unavailable
            default:
                return .failed
            }
        } catch {
            return .failed
        }
    }

    private func kind(from type: LABiometryType) -> BiometricKind {
        switch type {
        case .faceID: .faceID
        case .touchID: .touchID
        case .opticID: .opticID
        default: .none
        }
    }
}

struct UnavailableBiometricAuthService: BiometricAuthenticating {
    func availability() -> BiometricAvailability { .unavailable }
    func authenticate(reason: String) async -> BiometricAuthResult { .unavailable }
}

struct StubBiometricAuthService: BiometricAuthenticating {
    var availabilityValue: BiometricAvailability
    var result: BiometricAuthResult

    func availability() -> BiometricAvailability { availabilityValue }
    func authenticate(reason: String) async -> BiometricAuthResult { result }
}
