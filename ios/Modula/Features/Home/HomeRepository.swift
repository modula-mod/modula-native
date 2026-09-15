import Foundation

protocol HomeRepository: Sendable {
    func page(mode: HomeMode, cursor: String?) async throws -> HomePage
    func refresh(mode: HomeMode) async throws -> HomePage
    func like(postID: SocialPostID) async throws
    func unlike(postID: SocialPostID) async throws
    func save(postID: SocialPostID) async throws
    func unsave(postID: SocialPostID) async throws
    func repost(postID: SocialPostID) async throws
    func unrepost(postID: SocialPostID) async throws
    func post(id: SocialPostID) async throws -> SocialPost
}

actor GreenfieldHomeRepository: HomeRepository {
    private let client: GreenfieldClient
    private var cache: [HomeMode: HomePage] = [:]

    init(client: GreenfieldClient) {
        self.client = client
    }

    func cachedPage(mode: HomeMode) -> HomePage? { cache[mode] }

    func page(mode: HomeMode, cursor: String?) async throws -> HomePage {
        var path = "/v1/feed/home?mode=\(mode.apiQueryValue)&limit=30"
        if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&cursor=\(encoded)"
        }
        let value: JSONValue
        if mode.requiresAuth {
            value = try await client.authenticatedJSON("GET", path: path)
        } else {
            value = try await client.json("GET", path: path)
        }
        let page = SocialPayloadDecoder.homePage(from: value)
        if cursor == nil { cache[mode] = page }
        return page
    }

    func refresh(mode: HomeMode) async throws -> HomePage {
        try await page(mode: mode, cursor: nil)
    }

    func like(postID: SocialPostID) async throws {
        let _: JSONValue = try await client.authenticatedJSON(
            "POST",
            path: "/v1/posts/\(Self.pathEscaped(postID))/like",
            body: .object([:])
        )
    }

    func unlike(postID: SocialPostID) async throws {
        let _: JSONValue = try await client.authenticatedJSON(
            "DELETE",
            path: "/v1/posts/\(Self.pathEscaped(postID))/like",
            body: nil
        )
    }

    func save(postID: SocialPostID) async throws {
        let _: JSONValue = try await client.authenticatedJSON(
            "POST",
            path: "/v1/posts/\(Self.pathEscaped(postID))/save",
            body: .object([:])
        )
    }

    func unsave(postID: SocialPostID) async throws {
        let _: JSONValue = try await client.authenticatedJSON(
            "DELETE",
            path: "/v1/posts/\(Self.pathEscaped(postID))/save",
            body: nil
        )
    }

    func repost(postID: SocialPostID) async throws {
        let _: JSONValue = try await client.authenticatedJSON(
            "POST",
            path: "/v1/posts/\(Self.pathEscaped(postID))/repost",
            body: .object([:])
        )
    }

    func unrepost(postID: SocialPostID) async throws {
        let _: JSONValue = try await client.authenticatedJSON(
            "DELETE",
            path: "/v1/posts/\(Self.pathEscaped(postID))/repost",
            body: nil
        )
    }

    func post(id: SocialPostID) async throws -> SocialPost {
        let value = try await client.json("GET", path: "/v1/posts/\(Self.pathEscaped(id))")
        let payload = value["post"] ?? value
        guard let post = SocialPayloadDecoder.post(payload) else {
            throw APIError.invalidResponse
        }
        return post
    }

    nonisolated private static func pathEscaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}
