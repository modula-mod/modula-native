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
    /// True while our own LAContext prompt is on screen. The Face ID sheet makes the
    /// scene go .inactive → .active; that must never relock or show the privacy cover.
    private(set) var isAuthenticating = false
    /// Armed on cold launch and after a real background relock; consumed by the lock
    /// screen so Face ID auto-prompts at most once per foreground.
    private var autoPromptArmed = false

    init(
        credentials: AppLockCredentialStoring = AppLockCredentialStore(),
        biometrics: BiometricAuthenticating = SystemBiometricAuthService(),
        defaults: UserDefaults = .standard,
        startsLockedIfEnabled: Bool = true
    ) {
        self.credentials = credentials
        self.biometrics = biometrics
        self.defaults = defaults
        if credentials is AppLockCredentialStore { AppLockCredentialStore.purgeRetiredVerifiers() }
        var settings = defaults.data(forKey: settingsKey).flatMap {
            try? JSONDecoder().decode(AppLockSettings.self, from: $0)
        } ?? .default
        let hasPasscode = (try? credentials.hasPasscode()) == true
        if !hasPasscode {
            settings.enabled = false
        }
        if settings.method != .passcode,
           (try? credentials.hasSecret(settings.method.secretKind)) != true {
            settings.method = .passcode
        }
        self.settings = settings
        // Restore rate limiting across relaunches so killing the app doesn't reset it.
        let savedFailures = defaults.integer(forKey: "modula.native.applock.failures.v1")
        self.failedAttempts = savedFailures
        if let until = defaults.object(forKey: "modula.native.applock.cooldown.v1") as? Date, until > Date() {
            self.cooldownUntil = ContinuousClock.now.advanced(by: .seconds(until.timeIntervalSinceNow))
        }
        self.isLocked = startsLockedIfEnabled && settings.enabled && hasPasscode
        self.autoPromptArmed = isLocked
    }

    /// Returns true exactly once per lock-from-foreground, and only when Face ID is usable.
    func consumeAutoPrompt() -> Bool {
        guard autoPromptArmed, isLocked, !isAuthenticating, canUseBiometrics else { return false }
        autoPromptArmed = false
        return true
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
        autoPromptArmed = true
    }

    func recordBackground() {
        guard !isAuthenticating else { return }
        backgroundedAt = ContinuousClock.now
        if settings.interval == .immediately, settings.enabled, !isLocked {
            isLocked = true
            autoPromptArmed = true
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
        // Only a real trip to the background can relock. An .inactive → .active bounce
        // (Face ID sheet, Control Centre, notification shade) leaves the lock state alone.
        guard !isAuthenticating, let backgroundedAt else { return }
        self.backgroundedAt = nil
        if settings.interval == .immediately || ContinuousClock.now - backgroundedAt >= settings.interval.duration {
            if !isLocked { autoPromptArmed = true }
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
        persistFailures()
    }

    // MARK: - Methods, effects, alternative secrets

    var attemptsBeforeCooldown: Int {
        max(0, AppLockAttemptPolicy.freeAttempts - failedAttempts)
    }

    func hasSecret(for method: AppLockMethod) -> Bool {
        (try? credentials.hasSecret(method.secretKind)) == true
    }

    /// Stores a pattern/Orbit verifier (salted PBKDF2, Keychain, this device only) and switches to it.
    func setAlternativeSecret(_ value: String, for method: AppLockMethod) throws {
        guard method != .passcode else { try setPasscode(value); return }
        try credentials.setSecret(value, kind: method.secretKind)
        settings.method = method
        persist()
    }

    func setMethod(_ method: AppLockMethod) {
        guard method == .passcode || hasSecret(for: method) else { return }
        settings.method = method
        persist()
    }

    func setEffectsEnabled(_ value: Bool) { settings.effectsEnabled = value; persist() }
    func setShowsGreeting(_ value: Bool) { settings.showsGreeting = value; persist() }
    func setHidesPatternTrail(_ value: Bool) { settings.hidesPatternTrail = value; persist() }
    func setHapticsEnabled(_ value: Bool) { settings.hapticsEnabled = value; persist() }

    func haptic(_ semantic: HapticSemantic) {
        guard settings.hapticsEnabled else { return }
        HapticEngine.shared.play(semantic)
    }

    /// Verifies a pattern/Orbit attempt. Shares the passcode's attempt counter and cooldown.
    func unlock(withSecret value: String, method: AppLockMethod) -> Bool {
        if method == .passcode { return unlock(withPasscode: value) }
        if let cooldownUntil, ContinuousClock.now < cooldownUntil {
            lastError = "Too many attempts. Try again shortly."
            return false
        }
        do {
            if try credentials.verifySecret(value, kind: method.secretKind) {
                succeed()
                return true
            }
            registerFailure()
            lastError = switch method {
            case .pattern: "Wrong pattern."
            default: "Rings don’t line up."
            }
            return false
        } catch {
            lastError = "Lock storage is unavailable."
            return false
        }
    }

    private func succeed() {
        isLocked = false
        failedAttempts = 0
        cooldownUntil = nil
        lastError = nil
        persistFailures()
    }

    private func persistFailures() {
        defaults.set(failedAttempts, forKey: "modula.native.applock.failures.v1")
        if let cooldownUntil {
            let remaining = cooldownUntil - ContinuousClock.now
            let secs = Double(remaining.components.seconds) + Double(remaining.components.attoseconds) / 1e18
            defaults.set(Date().addingTimeInterval(max(0, secs)), forKey: "modula.native.applock.cooldown.v1")
        } else {
            defaults.removeObject(forKey: "modula.native.applock.cooldown.v1")
        }
    }

    func unlock(withPasscode passcode: String) -> Bool {
        if let cooldownUntil, ContinuousClock.now < cooldownUntil {
            lastError = "Too many attempts. Try again shortly."
            return false
        }
        do {
            let ok = try credentials.verifyPasscode(passcode)
            if ok {
                succeed()
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
        // Only one evaluatePolicy at a time.
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        let result = await biometrics.authenticate(reason: "Unlock Modula")
        isAuthenticating = false
        autoPromptArmed = false
        switch result {
        case .success:
            succeed()
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
        persistFailures()
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
        persistFailures()
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(settings), forKey: settingsKey)
    }
}
