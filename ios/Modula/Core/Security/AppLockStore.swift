import Foundation
import Observation

@MainActor @Observable
final class AppLockStore {
    private let credentials: AppLockCredentialStoring
    private let biometrics: BiometricAuthenticating
    private let defaults: UserDefaults
    private let settingsKey = "modula.native.applock.settings.v1"

    private(set) var settings: AppLockSettings
    private(set) var isLocked: Bool
    private(set) var failedAttempts = 0
    private(set) var cooldownUntil: ContinuousClock.Instant?
    private(set) var lastError: String?
    private var backgroundedAt: ContinuousClock.Instant?

    init(
        credentials: AppLockCredentialStoring = AppLockCredentialStore(),
        biometrics: BiometricAuthenticating = SystemBiometricAuthService(),
        defaults: UserDefaults = .standard,
        startsLockedIfEnabled: Bool = true
    ) {
        self.credentials = credentials
        self.biometrics = biometrics
        self.defaults = defaults
        var settings = defaults.data(forKey: settingsKey).flatMap {
            try? JSONDecoder().decode(AppLockSettings.self, from: $0)
        } ?? .default
        let hasPasscode = (try? credentials.hasPasscode()) == true
        if !hasPasscode {
            settings.enabled = false
        }
        self.settings = settings
        self.isLocked = startsLockedIfEnabled && settings.enabled && hasPasscode
    }

    var enabled: Bool { settings.enabled }
    var requiresUnlock: Bool { settings.enabled && isLocked }
    var biometricAvailability: BiometricAvailability { biometrics.availability() }
    var canUseBiometrics: Bool { settings.biometricsEnabled && biometricAvailability.isUsable }
    var shouldCoverAppSwitcher: Bool { settings.hideInAppSwitcher || requiresUnlock }

    func refreshColdLaunchLock() {
        guard settings.enabled, (try? credentials.hasPasscode()) == true else {
            isLocked = false
            return
        }
        isLocked = true
    }

    func recordBackground() {
        backgroundedAt = ContinuousClock.now
        if settings.interval == .immediately, settings.enabled {
            isLocked = true
        }
    }

    func evaluateForeground() {
        guard settings.enabled else {
            isLocked = false
            return
        }
        guard (try? credentials.hasPasscode()) == true else {
            isLocked = false
            return
        }
        if settings.interval == .immediately {
            isLocked = true
            return
        }
        guard let backgroundedAt else {
            isLocked = true
            return
        }
        if ContinuousClock.now - backgroundedAt >= settings.interval.duration {
            isLocked = true
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard try credentials.hasPasscode() else {
                lastError = "Create a 6-digit Modula passcode first."
                throw APIError.secureStorage
            }
        }
        settings.enabled = enabled
        isLocked = enabled
        persist()
    }

    func setInterval(_ interval: AppLockInterval) {
        settings.interval = interval
        persist()
    }

    func setBiometricsEnabled(_ enabled: Bool) {
        settings.biometricsEnabled = enabled
        persist()
    }

    func setHideInAppSwitcher(_ enabled: Bool) {
        settings.hideInAppSwitcher = enabled
        persist()
    }

    func setPasscode(_ passcode: String) throws {
        try credentials.setPasscode(passcode)
        lastError = nil
        failedAttempts = 0
        cooldownUntil = nil
    }

    func unlock(withPasscode passcode: String) -> Bool {
        if let cooldownUntil, ContinuousClock.now < cooldownUntil {
            lastError = "Too many attempts. Try again shortly."
            return false
        }
        do {
            let ok = try credentials.verifyPasscode(passcode)
            if ok {
                isLocked = false
                failedAttempts = 0
                cooldownUntil = nil
                lastError = nil
                return true
            }
            registerFailure()
            lastError = "Incorrect passcode."
            return false
        } catch {
            lastError = "Passcode storage is unavailable."
            return false
        }
    }

    func unlockWithBiometrics() async -> Bool {
        guard canUseBiometrics else {
            lastError = biometricAvailability.explanation
            return false
        }
        let result = await biometrics.authenticate(reason: "Unlock Modula")
        switch result {
        case .success:
            isLocked = false
            lastError = nil
            return true
        case .cancelled:
            lastError = nil
            return false
        case .unavailable:
            lastError = biometricAvailability.explanation
            return false
        case .failed:
            lastError = "Biometric unlock didn’t succeed. Enter your Modula passcode."
            return false
        }
    }

    func remainingCooldown() -> Duration {
        guard let cooldownUntil else { return .seconds(0) }
        let remaining = cooldownUntil - ContinuousClock.now
        return remaining < .seconds(0) ? .seconds(0) : remaining
    }

    func resetAfterSignOut() {
        try? credentials.clear()
        settings = .default
        isLocked = false
        failedAttempts = 0
        cooldownUntil = nil
        lastError = nil
        defaults.removeObject(forKey: settingsKey)
    }

    func disableAndClearPasscode() throws {
        try credentials.clear()
        settings.enabled = false
        isLocked = false
        persist()
    }

    private func registerFailure() {
        failedAttempts += 1
        let delay = AppLockAttemptPolicy.delay(afterFailureCount: failedAttempts)
        if delay > .seconds(0) {
            cooldownUntil = ContinuousClock.now.advanced(by: delay)
        }
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(settings), forKey: settingsKey)
    }
}
