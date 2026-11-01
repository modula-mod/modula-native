import Foundation
import Observation

// MARK: - GUBIC (spec: docs/gubic/GUBIC-PLATFORM-SPEC.md)
//
// Everything reads real Greenfield routes. When a route is missing (backend not deployed, 404) or
// returns nothing, the UI shows an honest empty state. Nothing here invents games, players,
// achievements or prices.

enum GubicFeature {
    static let enabledKey = "dev.gubic.enabled"

    /// On by default in Debug so the surface can be reviewed, off in Release unless switched on.
    static func enabled(defaults: UserDefaults = .standard) -> Bool {
        if ProcessInfo.processInfo.arguments.contains("--gubic-disabled") { return false }
        #if DEBUG
        return defaults.object(forKey: enabledKey) as? Bool ?? true
        #else
        return defaults.bool(forKey: enabledKey)
        #endif
    }
}

enum GubicAPI {
    static let featured = "/v1/gubic/featured?limit=20"
    static let newReleases = "/v1/gubic/new-releases?limit=20"
    static let categories = "/v1/gubic/categories"
    static let games = "/v1/gubic/games?limit=100"
    static let library = "/v1/gubic/library"
    static let myGames = "/v1/gubic/my-games"
    static let capabilities = "/v1/gubic/capabilities"
    static let myAchievements = "/v1/gubic/me/achievements"
    static let submissions = "/v1/developer/gubic/submissions"
    static let joinLobby = "/v1/gubic/lobbies/join"
    static let developerBoard = "/v1/developer/board"

    static func encode(_ id: String) -> String { id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? id }
    static func game(_ id: String) -> String { "/v1/gubic/games/\(encode(id))" }
    static func achievements(_ id: String) -> String { "\(game(id))/achievements" }
    static func lobbies(_ id: String) -> String { "\(game(id))/lobbies" }
    static func sessions(_ id: String) -> String { "\(game(id))/sessions" }
    static func libraryItem(_ id: String) -> String { "/v1/gubic/library/\(encode(id))" }
    static func lobby(_ id: String) -> String { "/v1/gubic/lobbies/\(encode(id))" }
    static func lobbySocket(_ id: String) -> String { "\(lobby(id))/socket" }
    static func session(_ id: String) -> String { "/v1/gubic/sessions/\(encode(id))" }
    static func unlock(session: String, key: String) -> String { "\(self.session(session))/achievements/\(encode(key))" }
    static func submissions(publisher: String) -> String { "\(submissions)?publisherId=\(encode(publisher))" }
}

/// Distinguishes "the server has no such route yet" from real failures so screens can say so.
enum GubicLoadState: Equatable {
    case idle, loading, loaded, notDeployed, signedOut, failed(String)

    static func from(_ error: Error) -> GubicLoadState {
        switch error {
        case APIError.unauthenticated, APIError.rejected(401, _): .signedOut
        case APIError.rejected(404, _), APIError.rejected(_, "NOT_FOUND"): .notDeployed
        case let api as APIError: .failed(api.userFacingMessage)
        default: .failed(error.localizedDescription)
        }
    }
}

struct GubicGame: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let summary: String
    let publisher: String
    let publisherVerified: Bool
    let genre: String
    let categories: [String]
    let runtime: String
    let version: String
    let downloadBytes: Int?
    let ageRating: String?
    let availability: String
    let iconURL: URL?
    let coverURL: URL?

    init?(json: JSONValue) {
        guard let id = json["gameId"]?.string, let title = json["title"]?.string else { return nil }
        self.id = id
        self.title = title
        summary = json["description"]?.string ?? ""
        publisher = json["publisher"]?["displayName"]?.string ?? ""
        publisherVerified = json["publisher"]?["verified"]?.bool ?? false
        genre = json["genre"]?.string ?? ""
        categories = json["categories"]?.array?.compactMap(\.string) ?? []
        runtime = json["runtime"]?["engine"]?.string ?? json["runtime"]?["category"]?.string ?? ""
        version = json["release"]?["version"]?.string ?? ""
        downloadBytes = json["sizes"]?["downloadBytes"]?.int
        let age = json["ageClassification"]
        ageRating = age?["modula"]?.string ?? age?["rating"]?.string
        availability = json["availability"]?.string ?? "unavailable"
        let presentation = CataloguePresentation.from(json["presentation"])
        iconURL = presentation?.icon?.source
        coverURL = presentation?.cover?.source
    }
}

struct GubicLibraryItem: Identifiable, Hashable, Sendable {
    var id: String { gameId }
    let gameId: String
    let favourite: Bool
    let lastPlayedAt: String?
    let playCount: Int
    let totalPlaySeconds: Int
    let achievementsUnlocked: Int
    let game: GubicGame?

    init?(json: JSONValue) {
        guard let gameId = json["gameId"]?.string else { return nil }
        self.gameId = gameId
        favourite = json["favourite"]?.bool ?? false
        lastPlayedAt = json["lastPlayedAt"]?.string
        playCount = json["playCount"]?.int ?? 0
        totalPlaySeconds = json["totalPlaySeconds"]?.int ?? 0
        achievementsUnlocked = json["achievementsUnlocked"]?.int ?? 0
        game = json["game"].flatMap(GubicGame.init(json:))
    }
}

struct GubicAchievement: Identifiable, Hashable, Sendable {
    var id: String { key }
    let key: String
    let title: String
    let description: String
    let points: Int
    let unlockedAt: String?

    init?(json: JSONValue) {
        guard let key = json["key"]?.string else { return nil }
        self.key = key
        title = json["title"]?.string ?? key
        description = json["description"]?.string ?? ""
        points = json["points"]?.int ?? 0
        unlockedAt = json["unlockedAt"]?.string
    }

    init(key: String, title: String, description: String, points: Int, unlockedAt: String?) {
        self.key = key; self.title = title; self.description = description; self.points = points; self.unlockedAt = unlockedAt
    }
}

struct GubicLobby: Identifiable, Hashable, Sendable {
    struct Member: Hashable, Sendable { let handle: String; let role: String; let ready: Bool; let isYou: Bool }
    let id: String
    let gameId: String
    let title: String
    let visibility: String
    let status: String
    let maxPlayers: Int
    let playerCount: Int
    let revision: Int
    let joinCode: String?
    let isHost: Bool
    let members: [Member]

    init?(json: JSONValue) {
        guard let id = json["lobbyId"]?.string else { return nil }
        self.id = id
        gameId = json["gameId"]?.string ?? ""
        title = json["title"]?.string ?? "Lobby"
        visibility = json["visibility"]?.string ?? "public"
        status = json["status"]?.string ?? "open"
        maxPlayers = json["maxPlayers"]?.int ?? 0
        playerCount = json["playerCount"]?.int ?? 0
        revision = json["revision"]?.int ?? 0
        joinCode = json["joinCode"]?.string
        isHost = json["isHost"]?.bool ?? false
        members = json["members"]?.array?.map {
            Member(handle: $0["handle"]?.string ?? "", role: $0["role"]?.string ?? "player",
                   ready: $0["ready"]?.bool ?? false, isYou: $0["isYou"]?.bool ?? false)
        } ?? []
    }
}

struct GubicSubmission: Identifiable, Hashable, Sendable {
    let id: String
    let gameId: String
    let title: String
    let version: String
    let status: String
    let monetisation: String
    let decisionReason: String?

    init?(json: JSONValue) {
        guard let id = json["submissionId"]?.string else { return nil }
        self.id = id
        gameId = json["gameId"]?.string ?? ""
        title = json["title"]?.string ?? gameId
        version = json["version"]?.string ?? ""
        status = json["status"]?.string ?? ""
        monetisation = json["monetisation"]?.string ?? "free"
        decisionReason = json["decisionReason"]?.string
    }
}

/// Server-evaluated GUBIC Premium capabilities (`GET /v1/gubic/capabilities`). Fails closed.
struct GubicCapabilities: Equatable, Sendable {
    var tier: String?
    var available: [String: Bool] = [:]
    var values: [String: Int] = [:]
    var loaded = false

    func allows(_ id: String) -> Bool { loaded && (available[id] ?? false) }
    var lobbySize: Int? { loaded ? values["gubic_lobby_size"] : nil }

    init() {}
    init(json: JSONValue) {
        tier = json["tier"]?.string
        for item in json["capabilities"]?.array ?? [] {
            guard let id = item["id"]?.string else { continue }
            available[id] = item["available"]?.bool ?? false
            if let value = item["value"]?.int { values[id] = value }
        }
        loaded = true
    }
}

@MainActor
@Observable
final class GubicStore {
    private let client: GreenfieldClient

    var discoverState: GubicLoadState = .idle
    var featured: [GubicGame] = []
    var newReleases: [GubicGame] = []
    var allGames: [GubicGame] = []
    var categories: [(name: String, count: Int)] = []

    var libraryState: GubicLoadState = .idle
    var library: [GubicLibraryItem] = []

    var capabilities = GubicCapabilities()
    var capabilitiesState: GubicLoadState = .idle

    init(client: GreenfieldClient) { self.client = client }

    func loadDiscover() async {
        discoverState = .loading
        do {
            async let featuredValue = client.json("GET", path: GubicAPI.featured)
            async let newValue = client.json("GET", path: GubicAPI.newReleases)
            async let allValue = client.json("GET", path: GubicAPI.games)
            async let categoryValue = client.json("GET", path: GubicAPI.categories)
            let (f, n, a, c) = try await (featuredValue, newValue, allValue, categoryValue)
            featured = f["items"]?.array?.compactMap(GubicGame.init(json:)) ?? []
            newReleases = n["items"]?.array?.compactMap(GubicGame.init(json:)) ?? []
            allGames = a["items"]?.array?.compactMap(GubicGame.init(json:)) ?? []
            categories = c["items"]?.array?.compactMap { item in
                item["category"]?.string.map { ($0, item["gameCount"]?.int ?? 0) }
            } ?? []
            discoverState = .loaded
        } catch {
            discoverState = .from(error)
        }
    }

    func loadLibrary() async {
        libraryState = .loading
        do {
            let value = try await client.authenticatedJSON("GET", path: GubicAPI.library)
            library = value["items"]?.array?.compactMap(GubicLibraryItem.init(json:)) ?? []
            libraryState = .loaded
        } catch {
            libraryState = .from(error)
        }
    }

    func loadCapabilities() async {
        capabilitiesState = .loading
        do {
            capabilities = GubicCapabilities(json: try await client.authenticatedJSON("GET", path: GubicAPI.capabilities))
            capabilitiesState = .loaded
        } catch {
            capabilities = GubicCapabilities()
            capabilitiesState = .from(error)
        }
    }

    func game(_ id: String) async throws -> GubicGame? {
        GubicGame(json: try await client.json("GET", path: GubicAPI.game(id)))
    }

    func achievements(for id: String) async throws -> [GubicAchievement] {
        let value = try await client.json("GET", path: GubicAPI.achievements(id))
        return value["items"]?.array?.compactMap(GubicAchievement.init(json:)) ?? []
    }

    func addToLibrary(_ id: String) async throws {
        _ = try await client.authenticatedJSON("PUT", path: GubicAPI.libraryItem(id), body: .object([:]))
        await loadLibrary()
    }

    func removeFromLibrary(_ id: String) async throws {
        _ = try await client.authenticatedJSON("DELETE", path: GubicAPI.libraryItem(id))
        await loadLibrary()
    }

    // Sessions
    func startSession(gameId: String, lobbyId: String? = nil) async throws -> String? {
        var body: [String: JSONValue] = ["clientPlatform": .string("ios")]
        if let lobbyId { body["lobbyId"] = .string(lobbyId) }
        return try await client.authenticatedJSON("POST", path: GubicAPI.sessions(gameId), body: .object(body))["sessionId"]?.string
    }

    func heartbeat(sessionId: String) async { _ = try? await client.authenticatedJSON("POST", path: GubicAPI.session(sessionId) + "/heartbeat", body: .object([:])) }
    func endSession(sessionId: String) async { _ = try? await client.authenticatedJSON("POST", path: GubicAPI.session(sessionId) + "/end", body: .object([:])) }

    func unlock(sessionId: String, key: String) async throws -> (title: String, points: Int, new: Bool) {
        let value = try await client.authenticatedJSON("POST", path: GubicAPI.unlock(session: sessionId, key: key), body: .object([:]))
        return (value["title"]?.string ?? key, value["points"]?.int ?? 0, value["newlyUnlocked"]?.bool ?? false)
    }

    // Lobbies
    func lobbies(gameId: String) async throws -> [GubicLobby] {
        try await client.authenticatedJSON("GET", path: GubicAPI.lobbies(gameId))["items"]?.array?.compactMap(GubicLobby.init(json:)) ?? []
    }
    func lobby(_ id: String) async throws -> GubicLobby? { GubicLobby(json: try await client.authenticatedJSON("GET", path: GubicAPI.lobby(id))) }
    func createLobby(gameId: String, title: String, invite: Bool, maxPlayers: Int) async throws -> GubicLobby? {
        GubicLobby(json: try await client.authenticatedJSON("POST", path: GubicAPI.lobbies(gameId), body: .object([
            "title": .string(title), "visibility": .string(invite ? "invite" : "public"), "maxPlayers": .number(Double(maxPlayers)),
        ])))
    }
    func joinLobby(code: String) async throws -> GubicLobby? {
        GubicLobby(json: try await client.authenticatedJSON("POST", path: GubicAPI.joinLobby, body: .object(["joinCode": .string(code)])))
    }
    func joinLobby(id: String) async throws -> GubicLobby? {
        GubicLobby(json: try await client.authenticatedJSON("POST", path: GubicAPI.lobby(id) + "/join", body: .object([:])))
    }
    func leaveLobby(_ id: String) async throws { _ = try await client.authenticatedJSON("POST", path: GubicAPI.lobby(id) + "/leave", body: .object([:])) }
    func setReady(_ id: String, ready: Bool) async throws -> GubicLobby? {
        GubicLobby(json: try await client.authenticatedJSON("POST", path: GubicAPI.lobby(id) + "/ready", body: .object(["ready": .bool(ready)])))
    }
    func startLobby(_ id: String) async throws -> GubicLobby? {
        GubicLobby(json: try await client.authenticatedJSON("POST", path: GubicAPI.lobby(id) + "/start", body: .object([:])))
    }
    func lobbySocketRequest(_ id: String) async throws -> URLRequest { try await client.webSocketRequest(path: GubicAPI.lobbySocket(id)) }

    // Creator
    func publisherIDs() async throws -> [String] {
        let board = try await client.authenticatedJSON("GET", path: GubicAPI.developerBoard)
        // The developer board lists products; each carries its publisher.
        let ids = board["products"]?.array?.compactMap { $0["publisherId"]?.string } ?? []
        return Array(Set(ids)).sorted()
    }
    func submissions(publisher: String) async throws -> [GubicSubmission] {
        try await client.authenticatedJSON("GET", path: GubicAPI.submissions(publisher: publisher))["items"]?.array?.compactMap(GubicSubmission.init(json:)) ?? []
    }
}
