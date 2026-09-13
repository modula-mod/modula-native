import Foundation

enum APIError: Error, LocalizedError {
    case unconfigured, unauthenticated, secureStorage, invalidResponse, accountChanged
    case rejected(Int, String)
    var errorDescription: String? {
        switch self {
        case .unconfigured: "Greenfield is not configured."
        case .unauthenticated: "Sign in to Modula to continue."
        case .secureStorage: "Secure session storage is unavailable."
        case .invalidResponse: "Greenfield returned an unsupported response."
        case .accountChanged: "The account changed. Open the module again."
        case .rejected(let status, let code): "Greenfield request failed (\(status), \(code))."
        }
    }
}
struct GreenfieldAccount: Codable, Sendable {
    let accountId: String
    let primaryHandle: String
    let status: String
}
struct CatalogueProduct: Codable, Sendable, Identifiable, Hashable {
    var id: String { moduleId }
    let moduleId: String
    let productKind: String
    let name: String
    let description: String
    let publisherId: String
    let publisherName: String
    let latestVersion: String?
    let status: String
    let installable: Bool
    let platforms: [String]
    let betaClassification: String?
    let installability: Installability?
    struct Installability: Codable, Sendable, Hashable { let status: String; let reasonCode: String?; let reason: String? }
}
private struct CataloguePage: Codable, Sendable { let items: [CatalogueProduct] }
private struct SessionTokens: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let sessionId: String
    let accessExpiresAt: String
    let refreshExpiresAt: String
    var accessValid: Bool {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: accessExpiresAt) ?? ISO8601DateFormatter().date(from: accessExpiresAt)
        return (date?.timeIntervalSinceNow ?? 0) > 30
    }
}
private struct Envelope<T: Decodable>: Decodable {
    let ok: Bool
    let data: T?
    let error: Failure?
    struct Failure: Decodable { let code: String }
}

actor GreenfieldClient {
    private let baseURL: URL?
    private let transport: URLSession
    private let keychain: KeychainStore
    private var tokens: SessionTokens?
    private var refreshTask: Task<SessionTokens, Error>?
    private var epoch = 0
    private var accountID: String?
    init(baseURL: URL?, transport: URLSession = .shared) {
        self.keychain = KeychainStore(namespace: baseURL?.absoluteString ?? "unconfigured")
        self.baseURL = baseURL
        self.transport = transport
    }
    func restore() async throws -> GreenfieldAccount? {
        guard let data = try keychain.load() else { return nil }
        tokens = try JSONDecoder().decode(SessionTokens.self, from: data)
        _ = try await accessToken()
        let account: GreenfieldAccount = try await authenticated("GET", path: "/v1/accounts/me")
        guard account.status == "active" else { throw APIError.unauthenticated }
        accountID = account.accountId
        return account
    }
    func signIn(email: String, password: String) async throws -> GreenfieldAccount {
        epoch += 1
        let generation = epoch
        refreshTask?.cancel(); refreshTask = nil
        let issued: SessionTokens = try await send("POST", path: "/v1/sessions", body: .object(["email": .string(email), "password": .string(password)]))
        let account: GreenfieldAccount = try await send("GET", path: "/v1/accounts/me", bearer: issued.accessToken)
        guard generation == epoch, account.status == "active" else { throw APIError.accountChanged }
        try keychain.save(JSONEncoder().encode(issued))
        tokens = issued; accountID = account.accountId
        return account
    }
    func signOut() async throws {
        let bearer = tokens?.accessToken
        epoch += 1; refreshTask?.cancel(); refreshTask = nil
        tokens = nil; accountID = nil
        try keychain.clear()
        if let bearer { let _: JSONValue = try await send("DELETE", path: "/v1/sessions/current", bearer: bearer) }
    }
    func catalogue() async throws -> [CatalogueProduct] {
        let page: CataloguePage = try await send("GET", path: "/v1/registry/products")
        return page.items
    }
    func installedModuleIDs() async throws -> Set<String> {
        let value: JSONValue = try await authenticated("GET", path: "/v1/modules/installed")
        return Self.installedIDs(from: value)
    }
    nonisolated static func installedIDs(from value: JSONValue) -> Set<String> {
        let items: [JSONValue]
        if case .array(let values) = value { items = values }
        else if case .array(let values) = value["items"] { items = values }
        else { return [] }
        return Set(items.compactMap { item in
            item["moduleId"]?.string ?? item["module_id"]?.string ?? item["productId"]?.string
        })
    }
    func moduleRequest(method: String, path: String, body: JSONValue?, expectedAccountID: String) async throws -> JSONValue {
        guard accountID == expectedAccountID else { throw APIError.accountChanged }
        let generation = epoch
        let result: JSONValue = try await authenticated(method, path: path, body: body)
        guard generation == epoch, accountID == expectedAccountID else { throw APIError.accountChanged }
        return result
    }
    private func authenticated<T: Decodable & Sendable>(_ method: String, path: String, body: JSONValue? = nil) async throws -> T {
        let generation = epoch
        let bearer = try await accessToken()
        let result: T = try await send(method, path: path, body: body, bearer: bearer)
        guard generation == epoch else { throw APIError.accountChanged }
        return result
    }
    private func accessToken() async throws -> String {
        if let refreshTask { return try await refreshTask.value.accessToken }
        guard let current = tokens else { throw APIError.unauthenticated }
        if current.accessValid { return current.accessToken }
        let generation = epoch
        let task = Task<SessionTokens, Error> {
            let next: SessionTokens = try await self.send("POST", path: "/v1/sessions/refresh", body: .object(["refreshToken": .string(current.refreshToken)]))
            guard generation == self.epoch else { throw APIError.accountChanged }
            try self.keychain.save(JSONEncoder().encode(next))
            self.tokens = next
            return next
        }
        refreshTask = task
        defer { if generation == epoch { refreshTask = nil } }
        do { return try await task.value.accessToken }
        catch {
            if generation == epoch {
                tokens = nil; accountID = nil
                try? keychain.clear()
            }
            throw error
        }
    }
    private func send<T: Decodable & Sendable>(_ method: String, path: String, body: JSONValue? = nil, bearer: String? = nil) async throws -> T {
        guard let baseURL, baseURL.scheme == "https", baseURL.user == nil, baseURL.password == nil,
              path.hasPrefix("/v1/"), !path.contains(".."), let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              url.host == baseURL.host else { throw APIError.unconfigured }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.setValue("ModulaNative/0.1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try body.map { try JSONEncoder().encode($0) }
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse, data.count < 8_000_000 else { throw APIError.invalidResponse }
        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        guard (200..<300).contains(http.statusCode), envelope.ok else {
            let rawCode = envelope.error?.code ?? "REQUEST_FAILED"
            let safeCode = rawCode.range(of: "^[A-Z0-9_]{1,80}$", options: .regularExpression) != nil ? rawCode : "REQUEST_FAILED"
            throw APIError.rejected(http.statusCode, safeCode)
        }
        guard let value = envelope.data else { throw APIError.invalidResponse }
        return value
    }
}
