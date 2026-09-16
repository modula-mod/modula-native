import CommonCrypto
import Foundation
import Security

/// Device-only passcode verifier. Never stores plaintext. Never syncs via iCloud Keychain.
struct AppLockCredentialStore: AppLockCredentialStoring {
    private let service = "digital.modula.app.native.applock"
    private let account = "passcode-verifier.v1"
    private let iterations = 100_000
    private let derivedLength = 32
    private let saltLength = 16

    func hasPasscode() throws -> Bool {
        try loadRecord() != nil
    }

    func setPasscode(_ passcode: String) throws {
        guard isValidPasscode(passcode) else { throw APIError.secureStorage }
        var salt = Data(count: saltLength)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, saltLength, $0.baseAddress!) }
        guard status == errSecSuccess else { throw APIError.secureStorage }
        let verifier = try derive(passcode: passcode, salt: salt)
        let record = Record(salt: salt, iterations: iterations, verifier: verifier)
        try save(record)
    }

    func verifyPasscode(_ passcode: String) throws -> Bool {
        guard let record = try loadRecord() else { return false }
        let candidate = try derive(passcode: passcode, salt: record.salt, iterations: record.iterations)
        return constantTimeEquals(candidate, record.verifier)
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw APIError.secureStorage }
    }

    private struct Record: Codable {
        var salt: Data
        var iterations: Int
        var verifier: Data
    }

    private func isValidPasscode(_ value: String) -> Bool {
        value.count == 6 && value.allSatisfy(\.isNumber)
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

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
    }

    private func loadRecord() throws -> Record? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw APIError.secureStorage }
        return try JSONDecoder().decode(Record.self, from: data)
    }

    private func save(_ record: Record) throws {
        let data = try JSONEncoder().encode(record)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        var status = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(baseQuery().merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw APIError.secureStorage }
    }
}

/// In-memory store for unit tests. Never used by production UI.
struct InMemoryAppLockCredentialStore: AppLockCredentialStoring {
    private class Box: @unchecked Sendable {
        var passcode: String?
    }
    private let box = Box()

    func hasPasscode() throws -> Bool { box.passcode != nil }

    func setPasscode(_ passcode: String) throws {
        box.passcode = passcode
    }

    func verifyPasscode(_ passcode: String) throws -> Bool {
        box.passcode == passcode
    }

    func clear() throws {
        box.passcode = nil
    }
}
