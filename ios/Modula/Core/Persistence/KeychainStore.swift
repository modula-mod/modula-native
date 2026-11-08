import Foundation
import Security

struct KeychainStore: Sendable {
    let namespace: String
    private let service = "digital.modula.app.native.session"
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: namespace] }
    func load() throws -> Data? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw failure("load", status) }
        return result as? Data
    }
    func save(_ data: Data) throws {
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound { status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) }
        guard status == errSecSuccess else { throw failure("save", status) }
    }
    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure("clear", status) }
    }

    /// Operation name and numeric OSStatus only. Never the query, namespace, or item bytes.
    private func failure(_ operation: String, _ status: OSStatus) -> APIError {
        ModulaLog.auth.error("keychain \(operation, privacy: .public) status=\(Int(status), privacy: .public)")
        return .secureStorage
    }
}
