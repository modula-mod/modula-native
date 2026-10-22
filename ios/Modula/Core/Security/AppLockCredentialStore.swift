import CommonCrypto
import Foundation
import Security

/// Device-only passcode verifier. Never stores plaintext. Never syncs via iCloud Keychain.
struct AppLockCredentialStore: AppLockCredentialStoring {
    private let service = "digital.modula.app.native.applock"
    private let iterations = 100_000
    private let derivedLength = 32
    private let saltLength = 16

    func hasPasscode() throws -> Bool { try hasSecret(.passcode) }
    func setPasscode(_ passcode: String) throws { try setSecret(passcode, kind: .passcode) }
    func verifyPasscode(_ passcode: String) throws -> Bool { try verifySecret(passcode, kind: .passcode) }

    func clear() throws {
        for kind in AppLockSecretKind.allCases { try clearSecret(kind) }
    }

    private func account(_ kind: AppLockSecretKind) -> String {
        switch kind {
        case .passcode: "passcode-verifier.v1"
        case .pattern: "pattern-verifier.v1"
        case .orbit: "orbit-verifier.v1"
        }
    }

    /// Deletes verifiers for retired unlock methods (Rhythm, Gravity, Seek, Cube, Constellation). Safe to call every launch.
    static func purgeRetiredVerifiers() {
        for account in ["rhythm-verifier.v1", "gravity-verifier.v1", "seek-verifier.v1", "cube-verifier.v1", "constellation-verifier.v1"] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "digital.modula.app.native.applock",
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(query as CFDictionary)
        }
    }

    func hasSecret(_ kind: AppLockSecretKind) throws -> Bool {
        try loadRecord(kind) != nil
    }

    func setSecret(_ passcode: String, kind: AppLockSecretKind) throws {
        guard isValid(passcode, kind: kind) else { throw APIError.secureStorage }
        var salt = Data(count: saltLength)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, saltLength, $0.baseAddress!) }
        guard status == errSecSuccess else { throw APIError.secureStorage }
        let verifier = try derive(passcode: passcode, salt: salt)
        let record = Record(salt: salt, iterations: iterations, verifier: verifier)
        try save(record, kind: kind)
    }

    func verifySecret(_ passcode: String, kind: AppLockSecretKind) throws -> Bool {
        guard let record = try loadRecord(kind) else { return false }
        let candidate = try derive(passcode: passcode, salt: record.salt, iterations: record.iterations)
        return constantTimeEquals(candidate, record.verifier)
    }

    func clearSecret(_ kind: AppLockSecretKind) throws {
        let status = SecItemDelete(baseQuery(kind) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw APIError.secureStorage }
    }

    private struct Record: Codable {
        var salt: Data
        var iterations: Int
        var verifier: Data
    }

    private func isValid(_ value: String, kind: AppLockSecretKind) -> Bool {
        switch kind {
        case .passcode: value.count == 6 && value.allSatisfy(\.isNumber)
        case .pattern: value.hasPrefix("pattern.v1:") && value.split(separator: "-").count >= PatternLock.minimumDots
        case .orbit: value.hasPrefix("orbit.v1:") && value.split(separator: "-").count == OrbitLock.rings.count
        }
    }

    private func derive(passcode: String, salt: Data, iterations: Int? = nil) throws -> Data {
        let rounds = UInt32(iterations ?? self.iterations)
        var derived = Data(count: derivedLength)
        let result: Int32 = derived.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                passcode.withCString { passwordPointer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordPointer,
                        passcode.utf8.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        rounds,
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        derivedLength
                    )
                }
            }
        }
        guard result == kCCSuccess else { throw APIError.secureStorage }
        return derived
    }

    private func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for index in 0..<lhs.count {
            difference |= lhs[index] ^ rhs[index]
        }
        return difference == 0
    }

    private func baseQuery(_ kind: AppLockSecretKind) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(kind),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
    }

    private func loadRecord(_ kind: AppLockSecretKind) throws -> Record? {
        var query = baseQuery(kind)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw APIError.secureStorage }
        return try JSONDecoder().decode(Record.self, from: data)
    }

    private func save(_ record: Record, kind: AppLockSecretKind) throws {
        let data = try JSONEncoder().encode(record)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        var status = SecItemUpdate(baseQuery(kind) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(baseQuery(kind).merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw APIError.secureStorage }
    }
}

/// In-memory store for unit tests. Never used by production UI.
struct InMemoryAppLockCredentialStore: AppLockCredentialStoring {
    private class Box: @unchecked Sendable {
        var secrets: [AppLockSecretKind: String] = [:]
    }
    private let box = Box()

    func hasPasscode() throws -> Bool { box.secrets[.passcode] != nil }
    func setPasscode(_ passcode: String) throws { box.secrets[.passcode] = passcode }
    func verifyPasscode(_ passcode: String) throws -> Bool { box.secrets[.passcode] == passcode }
    func clear() throws { box.secrets = [:] }
    func hasSecret(_ kind: AppLockSecretKind) throws -> Bool { box.secrets[kind] != nil }
    func setSecret(_ value: String, kind: AppLockSecretKind) throws { box.secrets[kind] = value }
    func verifySecret(_ value: String, kind: AppLockSecretKind) throws -> Bool { box.secrets[kind] == value }
    func clearSecret(_ kind: AppLockSecretKind) throws { box.secrets[kind] = nil }
}
