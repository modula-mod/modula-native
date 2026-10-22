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
    func hasSecret(_ kind: AppLockSecretKind) throws -> Bool
    func setSecret(_ value: String, kind: AppLockSecretKind) throws
    func verifySecret(_ value: String, kind: AppLockSecretKind) throws -> Bool
    func clearSecret(_ kind: AppLockSecretKind) throws
}

/// Which secret a verifier belongs to. The 6-digit passcode is always the master
/// fallback; pattern and Orbit are optional faster unlocks layered on top.
enum AppLockSecretKind: String, CaseIterable, Sendable {
    case passcode, pattern, orbit, rhythm, gravity
}

enum AppLockMethod: String, CaseIterable, Codable, Hashable, Sendable {
    case passcode, pattern, orbit, rhythm, gravity

    var title: String {
        switch self {
        case .passcode: "Passcode"
        case .pattern: "Pattern"
        case .orbit: "Orbit"
        case .rhythm: "Rhythm"
        case .gravity: "Gravity"
        }
    }

    var symbol: String {
        switch self {
        case .passcode: "circle.grid.3x3.fill"
        case .pattern: "point.3.connected.trianglepath.dotted"
        case .orbit: "circle.circle"
        case .rhythm: "metronome.fill"
        case .gravity: "circle.dotted.and.circle"
        }
    }

    var subtitle: String {
        switch self {
        case .passcode: "6-digit Modula passcode"
        case .pattern: "Draw a line through at least 4 dots"
        case .orbit: "Spin three glyph rings to your secret, like a dial"
        case .rhythm: "Tap your secret beat on Moliboo, with one or two fingers"
        case .gravity: "Tilt to roll a marble into your secret wells"
        }
    }

    var secretKind: AppLockSecretKind {
        switch self {
        case .passcode: .passcode
        case .pattern: .pattern
        case .orbit: .orbit
        case .rhythm: .rhythm
        case .gravity: .gravity
        }
    }
}

/// Orbit: three rings of glyphs. The secret is one glyph per ring, lined up at the top marker.
enum OrbitLock {
    static let rings: [[String]] = [
        ["sparkle", "moon.fill", "sun.max.fill", "leaf.fill", "flame.fill", "drop.fill", "bolt.fill", "snowflake",
         "star.fill", "heart.fill", "cloud.fill", "bell.fill", "music.note", "camera.fill", "gift.fill", "crown.fill"],
        ["triangle.fill", "square.fill", "circle.fill", "diamond.fill", "hexagon.fill", "seal.fill", "shield.fill", "pentagon.fill",
         "octagon.fill", "capsule.fill", "rhombus.fill", "staroflife.fill", "suit.club.fill", "suit.spade.fill", "suit.heart.fill", "suit.diamond.fill"],
        ["a.circle.fill", "b.circle.fill", "c.circle.fill", "d.circle.fill", "e.circle.fill", "f.circle.fill", "g.circle.fill", "h.circle.fill",
         "1.circle.fill", "2.circle.fill", "3.circle.fill", "4.circle.fill", "5.circle.fill", "6.circle.fill", "7.circle.fill", "8.circle.fill"],
    ]

    /// Canonical secret string from the glyph index each ring shows at the marker.
    static func encode(_ indices: [Int]) -> String {
        "orbit.v1:" + indices.map(String.init).joined(separator: "-")
    }
}

/// Rhythm: a secret beat of 4–8 taps. Each tap is one or two fingers; each gap is quantized to
/// short/long relative to the user's own tempo (geometric mean of their shortest and longest gap),
/// so the same beat played faster or slower still matches.
enum RhythmLock {
    static let minimumTaps = 4
    static let maximumTaps = 8

    struct Tap: Equatable { var fingers: Int; var time: TimeInterval }

    static func quantize(_ taps: [Tap]) -> [Bool] {
        guard taps.count > 1 else { return [] }
        let gaps = zip(taps.dropFirst(), taps).map { max(0.01, $0.time - $1.time) }
        guard let mn = gaps.min(), let mx = gaps.max(), mx / mn >= 1.7 else { return gaps.map { _ in false } }
        let threshold = (mn * mx).squareRoot()
        return gaps.map { $0 > threshold }
    }

    /// e.g. "rhythm.v1:1-2S-1L-1S" (finger count, then S/L for the gap before that tap).
    static func encode(_ taps: [Tap]) -> String {
        let longs = quantize(taps)
        let tokens = taps.enumerated().map { i, tap -> String in
            let f = String(min(2, max(1, tap.fingers)))
            return i == 0 ? f : f + (longs[i - 1] ? "L" : "S")
        }
        return "rhythm.v1:" + tokens.joined(separator: "-")
    }

    /// 0 weak, 1 okay, 2 strong.
    static func strength(_ taps: [Tap]) -> Int {
        let longs = quantize(taps)
        var score = taps.count
        if Set(taps.map { min(2, $0.fingers) }).count > 1 { score += 2 }
        if longs.contains(true) && longs.contains(false) { score += 2 }
        return score >= 10 ? 2 : score >= 7 ? 1 : 0
    }
}

/// Gravity: tilt the phone to roll a marble into glyph wells in a secret order. Wells are
/// reshuffled every unlock, so the tilt directions an onlooker sees reveal nothing.
enum GravityLock {
    static let glyphs = ["moon.fill", "sun.max.fill", "leaf.fill", "flame.fill", "drop.fill",
                         "bolt.fill", "snowflake", "star.fill", "heart.fill"]
    static let minimumWells = 4
    static let maximumWells = 6
    static func encode(_ sequence: [Int]) -> String {
        "gravity.v1:" + sequence.map(String.init).joined(separator: "-")
    }
    static func strength(_ sequence: [Int]) -> Int {
        let distinct = Set(sequence).count
        return sequence.count >= 6 && distinct >= 5 ? 2 : (sequence.count >= 5 || distinct >= 4) ? 1 : 0
    }
}

enum PatternLock {
    static let minimumDots = 4
    static func encode(_ nodes: [Int]) -> String {
        "pattern.v1:" + nodes.map(String.init).joined(separator: "-")
    }
}

struct AppLockSettings: Codable, Equatable, Sendable {
    var enabled: Bool
    var interval: AppLockInterval
    var biometricsEnabled: Bool
    var hideInAppSwitcher: Bool
    var method: AppLockMethod = .passcode
    var effectsEnabled: Bool = true
    var showsGreeting: Bool = true
    var hidesPatternTrail: Bool = false
    var hapticsEnabled: Bool = true

    static let `default` = AppLockSettings(
        enabled: false,
        interval: .immediately,
        biometricsEnabled: true,
        hideInAppSwitcher: true
    )

    init(enabled: Bool, interval: AppLockInterval, biometricsEnabled: Bool, hideInAppSwitcher: Bool) {
        self.enabled = enabled
        self.interval = interval
        self.biometricsEnabled = biometricsEnabled
        self.hideInAppSwitcher = hideInAppSwitcher
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        interval = try c.decodeIfPresent(AppLockInterval.self, forKey: .interval) ?? .immediately
        biometricsEnabled = try c.decodeIfPresent(Bool.self, forKey: .biometricsEnabled) ?? true
        hideInAppSwitcher = try c.decodeIfPresent(Bool.self, forKey: .hideInAppSwitcher) ?? true
        method = try c.decodeIfPresent(AppLockMethod.self, forKey: .method) ?? .passcode
        effectsEnabled = try c.decodeIfPresent(Bool.self, forKey: .effectsEnabled) ?? true
        showsGreeting = try c.decodeIfPresent(Bool.self, forKey: .showsGreeting) ?? true
        hidesPatternTrail = try c.decodeIfPresent(Bool.self, forKey: .hidesPatternTrail) ?? false
        hapticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
    }
}

enum AppLockAttemptPolicy {
    static let freeAttempts = 4

    static func delay(afterFailureCount count: Int) -> Duration {
        switch count {
        case ...4: .seconds(0)
        case 5: .seconds(30)
        case 6: .seconds(60)
        case 7: .seconds(300)
        case 8: .seconds(900)
        default: .seconds(3600)
        }
    }
}
