import Foundation

enum APIError: Error, LocalizedError, Equatable {
    case unconfigured, unauthenticated, secureStorage, invalidResponse, accountChanged
    case rejected(Int, String)

    var errorDescription: String? { userFacingMessage }

    /// Safe copy for UI. Raw status/code stay available via `diagnosticDescription`.
    var userFacingMessage: String {
        switch self {
        case .unconfigured: "Greenfield is not configured."
        case .unauthenticated: "Sign in to Modula to continue."
        case .secureStorage: "Secure session storage is unavailable."
        case .invalidResponse: "Greenfield returned an unsupported response."
        case .accountChanged: "The account changed. Open the module again."
        case .rejected(_, "INVALID_CREDENTIALS"): "Email or password is incorrect."
        case .rejected(_, "UNAUTHENTICATED"): "Sign in to Modula to continue."
        case .rejected(_, "ACCOUNT_INACTIVE"), .rejected(_, "ACCOUNT_DISABLED"):
            "This account is not active. Verify your email or contact support."
        case .rejected(_, "EMAIL_NOT_VERIFIED"), .rejected(_, "VERIFICATION_REQUIRED"):
            "Verify your email before signing in."
        case .rejected(_, "RATE_LIMITED"), .rejected(_, "TOO_MANY_REQUESTS"):
            "Too many attempts. Try again shortly."
        case .rejected(_, "VALIDATION_FAILED"): "Check the details you entered and try again."
        case .rejected(413, _), .rejected(_, "PAYLOAD_TOO_LARGE"):
            "That file is too large to upload. Try a smaller photo."
        case .rejected(_, "SERVER_UNAVAILABLE"):
            "Modula is having trouble right now. Try again in a moment."
        case .rejected(let status, _) where status >= 500:
            "Modula is having trouble right now. Try again in a moment."
        case .rejected: "Unable to complete the request. Try again."
        }
    }

    var diagnosticDescription: String {
        switch self {
        case .rejected(let status, let code): "Greenfield request failed (\(status), \(code))."
        default: userFacingMessage
        }
    }

    var code: String? {
        if case .rejected(_, let code) = self { return code }
        return nil
    }
}

struct GreenfieldAccount: Codable, Sendable, Equatable {
    let accountId: String
    let primaryHandle: String
    let status: String
    let email: String?
    let displayName: String?

    init(accountId: String, primaryHandle: String, status: String, email: String? = nil, displayName: String? = nil) {
        self.accountId = accountId
        self.primaryHandle = primaryHandle
        self.status = status
        self.email = email
        self.displayName = displayName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accountId = try c.decode(String.self, forKey: .accountId)
        primaryHandle = try c.decode(String.self, forKey: .primaryHandle)
        status = try c.decode(String.self, forKey: .status)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
    }

    private enum CodingKeys: String, CodingKey {
        case accountId, primaryHandle, status, email, displayName
    }
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
    /// Registry art for the latest published version (`presentation` on list items).
    var presentation: CataloguePresentation? = nil
    struct Installability: Codable, Sendable, Hashable { let status: String; let reasonCode: String?; let reason: String? }
}

/// Icon, cover and screenshots the registry serves for a product's latest published
/// version. URLs are registry asset URLs; anything missing means "draw a placeholder".
struct CataloguePresentation: Codable, Sendable, Hashable {
    var version: String?
    var icon: Asset?
    var cover: Asset?
    var screenshots: [Asset]?
    struct Asset: Codable, Sendable, Hashable {
        var url: String?
        var sha256: String?
        var width: Double?
        var height: Double?
        var alt: String?
        var available: Bool?
        /// Only available https assets are loaded.
        var source: URL? { available == false ? nil : ModuleListing.https(url) }
    }

    init(version: String? = nil, icon: Asset? = nil, cover: Asset? = nil, screenshots: [Asset]? = nil) {
        self.version = version; self.icon = icon; self.cover = cover; self.screenshots = screenshots
    }

    /// Lenient decode from a raw registry JSON value; nil when absent or malformed.
    static func from(_ value: JSONValue?) -> CataloguePresentation? {
        guard let value, value["icon"] != nil || value["cover"] != nil || value["screenshots"] != nil,
              let data = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(CataloguePresentation.self, from: data)
    }
}

/// The Modula host contract this app implements, as the registry evaluates it: the
/// Product Standard `compatibility.host` / frontend `hostRuntime` range and the adapter
/// manifest's `minimumModulaHostVersion`. It is NOT the App Store marketing version and
/// not a module's version. Bump it only when the app gains host APIs; the registry then
/// blocks (HOST_INCOMPATIBLE) only releases that genuinely require a newer host.
enum ModulaHost {
    static let version = "1.0.0"
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

struct PasswordResetRequestResult: Codable, Sendable {
    let requested: Bool
}

actor GreenfieldClient {
    private let baseURL: URL?
    private let transport: URLSession
    private let keychain: KeychainStore
    private var tokens: SessionTokens?
    private var refreshTask: Task<SessionTokens, Error>?
    private var epoch = 0
    private var accountID: String?
    private var sessionInvalidated: (@Sendable () -> Void)?

    /// Called (off the main actor) when the server rejects the session and a refresh
    /// can't recover it, so the app can leave the signed-in state instead of silently
    /// carrying a dead token (prod: POST /v1/stories → 401 after the session was revoked).
    func setSessionInvalidationHandler(_ handler: (@Sendable () -> Void)?) { sessionInvalidated = handler }

    /// Non-secret origin label for diagnostics (fixture vs production host).
    var apiOriginHost: String? { baseURL?.host }

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
        let issued: SessionTokens = try await send("POST", path: "/v1/sessions", body: .object([
            "email": .string(email),
            "password": .string(password)
        ]))
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

    func requestPasswordReset(email: String) async throws -> PasswordResetRequestResult {
        try await send("POST", path: "/v1/accounts/forgot-password", body: .object(["email": .string(email)]))
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

    /// Installations with their lifecycle status and version (`GET /v1/modules/installed`).
    func installedModules() async throws -> [ModuleInstallation] {
        let value: JSONValue = try await authenticated("GET", path: "/v1/modules/installed")
        return Self.installations(from: value)
    }

    nonisolated static func installations(from value: JSONValue) -> [ModuleInstallation] {
        let items = value.array ?? value["items"]?.array ?? []
        return items.compactMap { item in
            guard let id = item["moduleId"]?.string ?? item["module_id"]?.string ?? item["productId"]?.string else { return nil }
            return ModuleInstallation(moduleId: id, status: item["status"]?.string ?? "enabled", version: item["version"]?.string)
        }
    }

    /// Public store listing for one module (`GET /v1/registry/modules/:id`).
    func moduleListing(_ moduleID: String) async throws -> ModuleListing {
        guard let path = Self.modulePath(moduleID) else { throw APIError.invalidResponse }
        let value: JSONValue = try await send("GET", path: "/v1/registry/modules/\(path)")
        guard let listing = ModuleListing(json: value) else { throw APIError.invalidResponse }
        return listing
    }

    /// Lifecycle mutations. All are idempotent on the server via `idempotencyKey`, so the
    /// single 401-refresh retry in `authenticated` cannot double-apply them.
    func installModule(_ moduleID: String, version: String?, approvedPermissions: [String], idempotencyKey: String) async throws -> String? {
        guard let path = Self.modulePath(moduleID) else { throw APIError.invalidResponse }
        var body: [String: JSONValue] = ["platform": .string("ios"), "hostVersion": .string(ModulaHost.version), "idempotencyKey": .string(idempotencyKey)]
        if let version { body["version"] = .string(version) }
        if !approvedPermissions.isEmpty { body["approvedPermissions"] = .array(approvedPermissions.map(JSONValue.string)) }
        let value: JSONValue = try await authenticated("POST", path: "/v1/modules/\(path)/install", body: .object(body))
        return value["status"]?.string
    }

    func enableModule(_ moduleID: String, idempotencyKey: String) async throws {
        guard let path = Self.modulePath(moduleID) else { throw APIError.invalidResponse }
        let _: JSONValue = try await authenticated("POST", path: "/v1/modules/\(path)/enable", body: .object(["idempotencyKey": .string(idempotencyKey)]))
    }

    func updateModule(_ moduleID: String, version: String, approvedPermissionIncrease: Bool, idempotencyKey: String) async throws {
        guard let path = Self.modulePath(moduleID) else { throw APIError.invalidResponse }
        let _: JSONValue = try await authenticated("POST", path: "/v1/modules/\(path)/update", body: .object([
            "version": .string(version), "platform": .string("ios"), "hostVersion": .string(ModulaHost.version),
            "approvedPermissionIncrease": .bool(approvedPermissionIncrease), "idempotencyKey": .string(idempotencyKey),
        ]))
    }

    /// Registry versions of a module relative to this account's installation
    /// (`GET /v1/modules/:id/versions`), gated by registry trust and iOS compatibility.
    func moduleVersions(_ moduleID: String) async throws -> ModuleVersionList {
        guard let path = Self.modulePath(moduleID) else { throw APIError.invalidResponse }
        let value: JSONValue = try await authenticated("GET", path: "/v1/modules/\(path)/versions?platform=ios&hostVersion=\(ModulaHost.version)")
        guard let list = ModuleVersionList(json: value) else { throw APIError.invalidResponse }
        return list
    }

    /// Dry run of a version switch: permission changes, warnings and the target release's
    /// install descriptor (`POST /v1/modules/:id/version-preview`). Changes nothing.
    func previewModuleVersion(_ moduleID: String, version: String) async throws -> ModuleVersionPreview {
        guard let path = Self.modulePath(moduleID) else { throw APIError.invalidResponse }
        let value: JSONValue = try await authenticated("POST", path: "/v1/modules/\(path)/version-preview", body: .object([
            "version": .string(version), "platform": .string("ios"), "hostVersion": .string(ModulaHost.version),
        ]))
        guard let preview = ModuleVersionPreview(json: value) else { throw APIError.invalidResponse }
        return preview
    }

    /// Public registry facts for one immutable release, used to verify descriptors.
    func registryReleaseFacts(_ moduleID: String, version: String) async throws -> ModuleRegistryReleaseFacts {
        guard let path = Self.modulePath(moduleID),
              let encoded = version.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: ".-+"))) else { throw APIError.invalidResponse }
        let value: JSONValue = try await send("GET", path: "/v1/registry/modules/\(path)/versions/\(encoded)")
        guard let facts = ModuleRegistryReleaseFacts(json: value) else { throw APIError.invalidResponse }
        return facts
    }

    /// Switches an installation to an exact registry version (upgrade or downgrade). Returns
    /// the target release's install descriptor issued with the transition.
    func switchModuleVersion(_ moduleID: String, version: String, approvedPermissions: [String], acknowledgeDowngradeRisk: Bool, idempotencyKey: String) async throws -> ModuleInstallDescriptor? {
        guard let path = Self.modulePath(moduleID) else { throw APIError.invalidResponse }
        let value: JSONValue = try await authenticated("POST", path: "/v1/modules/\(path)/update", body: .object([
            "version": .string(version),
            "platform": .string("ios"),
            "hostVersion": .string(ModulaHost.version),
            "approvedPermissions": .array(approvedPermissions.map(JSONValue.string)),
            "acknowledgeDowngradeRisk": .bool(acknowledgeDowngradeRisk),
            "idempotencyKey": .string(idempotencyKey),
        ]))
        return value["descriptor"].flatMap(ModuleInstallDescriptor.init(json:))
    }

    /// Uninstall keeps the account's module data so a reinstall restores it.
    func uninstallModule(_ moduleID: String, idempotencyKey: String) async throws {
        guard let path = Self.modulePath(moduleID) else { throw APIError.invalidResponse }
        let _: JSONValue = try await authenticated("DELETE", path: "/v1/modules/\(path)/install", body: .object([
            "choice": .string("keepData"), "idempotencyKey": .string(idempotencyKey),
        ]))
    }

    /// Module ids are reverse-DNS; anything else never reaches a URL path.
    nonisolated static func modulePath(_ moduleID: String) -> String? {
        moduleID.range(of: "^[a-z][a-z0-9.-]{1,127}$", options: .regularExpression) == nil ? nil : moduleID
    }

    func moduleRequest(method: String, path: String, body: JSONValue?, expectedAccountID: String) async throws -> JSONValue {
        guard accountID == expectedAccountID else { throw APIError.accountChanged }
        let generation = epoch
        let result: JSONValue = try await authenticated(method, path: path, body: body, invalidatesOnRepeatedRejection: false)
        guard generation == epoch, accountID == expectedAccountID else { throw APIError.accountChanged }
        return result
    }

    /// Authenticated JSON fetch used by Activity and other native features.
    func authenticatedJSON(_ method: String, path: String, body: JSONValue? = nil, timeout: TimeInterval = 20) async throws -> JSONValue {
        try await authenticated(method, path: path, body: body, timeout: timeout)
    }

    /// Authenticated JSON with an `Idempotency-Key` header (account data requests, support cases).
    func authenticatedJSON(_ method: String, path: String, body: JSONValue? = nil, idempotencyKey: String) async throws -> JSONValue {
        guard Self.isSafeIdempotencyKey(idempotencyKey) else { throw APIError.invalidResponse }
        return try await authenticated(method, path: path, body: body, headers: ["Idempotency-Key": idempotencyKey])
    }

    nonisolated static func isSafeIdempotencyKey(_ key: String) -> Bool {
        key.range(of: "^[A-Za-z0-9._:-]{8,200}$", options: .regularExpression) != nil
    }

    /// Public JSON fetch (no bearer). Used by Discover/Search when signed out.
    func publicJSON(_ method: String, path: String, body: JSONValue? = nil) async throws -> JSONValue {
        try await send(method, path: path, body: body)
    }

    /// Prefer a restored session so `isFollowing` and similar viewer fields populate; fall back to public.
    func json(_ method: String, path: String, body: JSONValue? = nil) async throws -> JSONValue {
        if tokens != nil {
            return try await authenticated(method, path: path, body: body)
        }
        return try await send(method, path: path, body: body)
    }

    func hasSession() -> Bool { tokens != nil }

    #if DEBUG
    /// UITest-only: forget the local session without contacting the server.
    func discardLocalSession() {
        epoch += 1
        refreshTask?.cancel(); refreshTask = nil
        tokens = nil; accountID = nil
        try? keychain.clear()
    }
    #endif

    func authenticatedUpload(
        path: String,
        fileURL: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> JSONValue {
        guard let baseURL, baseURL.scheme == "https", baseURL.user == nil, baseURL.password == nil,
              path.hasPrefix("/v1/"), !path.contains(".."),
              let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              url.host == baseURL.host else { throw APIError.unconfigured }
        let generation = epoch
        let bearer = try await accessToken()
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("ModulaNative/0.1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        let transfer = UploadTransfer(progress: progress)
        let (data, response) = try await withTaskCancellationHandler {
            try await transfer.start(request: request, fileURL: fileURL)
        } onCancel: {
            transfer.cancel()
        }
        guard generation == epoch else { throw APIError.accountChanged }
        return try Self.decodeEnvelope(data, response: response, method: "PUT", path: path)
    }

    /// Loads media through the same authenticated session as JSON requests. Greenfield
    /// attachment URLs are deliberately protected; raw `AsyncImage`/`URLSession.shared`
    /// requests cannot satisfy that contract for private or owner-only content.
    func mediaData(from url: URL, maximumBytes: Int = 32_000_000) async throws -> Data {
        let request = try await mediaRequest(for: url)
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              data.count <= maximumBytes else { throw APIError.invalidResponse }
        return data
    }

    func downloadMedia(from url: URL) async throws -> URL {
        let request = try await mediaRequest(for: url)
        let (temporaryURL, response) = try await transport.download(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw APIError.invalidResponse
        }
        return temporaryURL
    }

    private func mediaRequest(for url: URL) async throws -> URLRequest {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("ModulaNative/0.1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        if url.host == baseURL?.host, url.path.hasPrefix("/v1/"), tokens != nil {
            request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func authenticated<T: Decodable & Sendable>(
        _ method: String, path: String, body: JSONValue? = nil, timeout: TimeInterval = 20,
        headers: [String: String] = [:], invalidatesOnRepeatedRejection: Bool = true
    ) async throws -> T {
        let generation = epoch
        let bearer = try await accessToken()
        do {
            let result: T = try await send(method, path: path, body: body, bearer: bearer, timeout: timeout, headers: headers)
            guard generation == epoch else { throw APIError.accountChanged }
            return result
        } catch APIError.rejected(401, _) where generation == epoch && tokens != nil {
            // The access token was rejected although it looked valid locally (revoked
            // session, clock skew). A 401 means the request wasn't processed, so refresh
            // once and retry; if the refresh is rejected too, the session is gone.
            let renewed = try await accessToken(forceRefresh: true, rejected: bearer)
            do {
                let result: T = try await send(method, path: path, body: body, bearer: renewed, timeout: timeout, headers: headers)
                guard generation == epoch else { throw APIError.accountChanged }
                return result
            } catch APIError.rejected(401, let code) where generation == epoch {
                // The refresh just succeeded, so the shell's own session is valid. For
                // module-scoped calls a repeated 401 is the module's rejection, not a
                // reason to sign the whole app out.
                guard invalidatesOnRepeatedRejection else { throw APIError.rejected(401, code) }
                invalidateSession()
                throw APIError.unauthenticated
            }
        }
    }

    private func invalidateSession() {
        epoch += 1
        refreshTask?.cancel(); refreshTask = nil
        tokens = nil; accountID = nil
        try? keychain.clear()
        sessionInvalidated?()
    }

    /// Only a definitive rejection of the refresh token ends the session. Offline, timeouts
    /// and 5xx keep the stored tokens so the user stays signed in and can retry.
    nonisolated static func refreshFailureEndsSession(_ error: Error) -> Bool {
        switch error {
        case APIError.rejected(let status, _): return status == 400 || status == 401 || status == 403
        case APIError.unauthenticated: return true
        default: return false
        }
    }

    private func accessToken(forceRefresh: Bool = false, rejected: String? = nil) async throws -> String {
        if let refreshTask { return try await refreshTask.value.accessToken }
        guard let current = tokens else { throw APIError.unauthenticated }
        // Another request may already have rotated the token that was rejected.
        if forceRefresh, let rejected, current.accessToken != rejected { return current.accessToken }
        if current.accessValid && !forceRefresh { return current.accessToken }
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
            if generation == epoch, Self.refreshFailureEndsSession(error) {
                invalidateSession()
                throw APIError.unauthenticated
            }
            throw error
        }
    }

    private func send<T: Decodable & Sendable>(
        _ method: String, path: String, body: JSONValue? = nil, bearer: String? = nil, timeout: TimeInterval = 20,
        headers: [String: String] = [:]
    ) async throws -> T {
        guard let baseURL, baseURL.scheme == "https", baseURL.user == nil, baseURL.password == nil,
              path.hasPrefix("/v1/"), !path.contains(".."), let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              url.host == baseURL.host else { throw APIError.unconfigured }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.setValue("ModulaNative/0.1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        for (field, value) in headers where field == "Idempotency-Key" { request.setValue(value, forHTTPHeaderField: field) }
        request.httpBody = try body.map { try JSONEncoder().encode($0) }
        let started = Date()
        let (data, response) = try await transport.data(for: request)
        if ModulaPreferences.verboseLogging {
            // Settings → Labs → "Verbose local logging": method, path (with the query
            // stripped), status, size and timing only — never headers or bodies.
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let safePath = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
            let elapsed = Int(Date().timeIntervalSince(started) * 1_000)
            ModulaLog.network.notice(
                "verbose \(method, privacy: .public) \(safePath, privacy: .public) → \(status, privacy: .public) \(data.count, privacy: .public)B \(elapsed, privacy: .public)ms"
            )
        }
        return try Self.decodeEnvelope(data, response: response, method: method, path: path)
    }

    /// Decodes a Greenfield envelope. Responses that are not envelopes (for example the
    /// nginx HTML 413 page in front of both hosts, or an HTML 502/503 from the edge) are
    /// mapped by status to safe `APIError` codes instead of surfacing a decoding error,
    /// and are logged without the body (which may echo request data).
    nonisolated static func decodeEnvelope<T: Decodable>(
        _ data: Data,
        response: URLResponse,
        method: String,
        path: String
    ) throws -> T {
        guard let http = response as? HTTPURLResponse, data.count < 8_000_000 else { throw APIError.invalidResponse }
        let envelope: Envelope<T>
        do {
            envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        } catch {
            let mapped = nonEnvelopeError(status: http.statusCode)
            let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
            ModulaLog.network.error(
                "Greenfield \(method, privacy: .public) \(path, privacy: .public) returned a non-envelope \(http.statusCode, privacy: .public) response (\(contentType, privacy: .public), \(data.count, privacy: .public) bytes) → \(mapped.diagnosticDescription, privacy: .public)"
            )
            throw mapped
        }
        guard (200..<300).contains(http.statusCode), envelope.ok else {
            let rawCode = envelope.error?.code ?? "REQUEST_FAILED"
            let safeCode = rawCode.range(of: "^[A-Z0-9_]{1,80}$", options: .regularExpression) != nil ? rawCode : "REQUEST_FAILED"
            if http.statusCode >= 500 || http.statusCode == 413 {
                ModulaLog.network.error(
                    "Greenfield \(method, privacy: .public) \(path, privacy: .public) failed \(http.statusCode, privacy: .public) \(safeCode, privacy: .public)"
                )
            }
            throw APIError.rejected(http.statusCode, safeCode)
        }
        guard let value = envelope.data else { throw APIError.invalidResponse }
        return value
    }

    /// Status-only mapping for bodies that are not Greenfield JSON.
    nonisolated static func nonEnvelopeError(status: Int) -> APIError {
        switch status {
        case 413: .rejected(413, "PAYLOAD_TOO_LARGE")
        case 429: .rejected(429, "RATE_LIMITED")
        case 500...599: .rejected(status, "SERVER_UNAVAILABLE")
        default: .invalidResponse
        }
    }
}

private final class UploadTransfer: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let progress: @Sendable (Double) -> Void
    private var received = Data()
    private var continuation: CheckedContinuation<(Data, URLResponse), Error>?
    private var task: URLSessionUploadTask?
    private var session: URLSession?

    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }

    func start(request: URLRequest, fileURL: URL) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
            self.session = session
            let task = session.uploadTask(with: request, fromFile: fileURL)
            self.task = task
            lock.unlock()
            progress(0)
            task.resume()
        }
    }

    func cancel() {
        lock.lock(); let task = task; lock.unlock()
        task?.cancel()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        progress(min(max(Double(totalBytesSent) / Double(totalBytesExpectedToSend), 0), 1))
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock(); received.append(data); lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let data = received
        let response = task.response
        self.task = nil
        self.session = nil
        lock.unlock()
        session.finishTasksAndInvalidate()
        if let error { continuation?.resume(throwing: error); return }
        guard let response else { continuation?.resume(throwing: APIError.invalidResponse); return }
        progress(1)
        continuation?.resume(returning: (data, response))
    }
}
