import Foundation

struct NodusSearchCredentialStore: Sendable {
    private let keychain: KeychainStore

    init(keychain: KeychainStore = KeychainStore(namespace: "developer.nodus.search.brave")) {
        self.keychain = keychain
    }

    func isConfigured() -> Bool {
        guard let data = try? keychain.load() else { return false }
        return !data.isEmpty
    }

    func loadKey() throws -> String? {
        guard let data = try keychain.load() else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func saveKey(_ value: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 12, key.count <= 512 else { throw NodusSearchError.invalidQuery }
        try keychain.save(Data(key.utf8))
    }

    func removeKey() throws { try keychain.clear() }
}

