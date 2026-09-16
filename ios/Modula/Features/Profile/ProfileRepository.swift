import Foundation

protocol ProfileRepository: Sendable {
    func profile(_ identity: ProfileIdentity, handleHint: String?) async throws -> ModulaProfile
    func posts(_ identity: ProfileIdentity, handle: String, cursor: String?) async throws -> ProfilePostPage
    func modules(featuredIDs: [String], catalogue: [CatalogueProduct]) async -> ProfileModulePage
    func followers(handle: String, cursor: String?) async throws -> ProfilePeoplePage
    func following(handle: String, cursor: String?) async throws -> ProfilePeoplePage
    func follow(profileID: ProfileID, handle: String) async throws -> ModulaProfile
    func unfollow(profileID: ProfileID, handle: String) async throws -> ModulaProfile
    func block(profileID: ProfileID) async throws
    func unblock(profileID: ProfileID) async throws
    func mute(profileID: ProfileID) async throws
    func unmute(profileID: ProfileID) async throws
    func report(profileID: ProfileID, category: String, details: String?) async throws
    func updateMe(_ draft: ProfileEditDraft) async throws -> ModulaProfile
}

actor GreenfieldProfileRepository: ProfileRepository {
    private let client: GreenfieldClient
    private var profileCache: [String: ModulaProfile] = [:]
    private var postsCache: [String: ProfilePostPage] = [:]
    private var followersCache: [String: ProfilePeoplePage] = [:]
    private var followingCache: [String: ProfilePeoplePage] = [:]
    private var modulesCache: [String: ProfileModulePage] = [:]

    init(client: GreenfieldClient) {
        self.client = client
    }

    func cachedProfile(key: String) -> ModulaProfile? { profileCache[key] }
    func cachedPosts(key: String) -> ProfilePostPage? { postsCache[key] }
    func cachedFollowers(key: String) -> ProfilePeoplePage? { followersCache[key] }
    func cachedFollowing(key: String) -> ProfilePeoplePage? { followingCache[key] }
    func cachedModules(key: String) -> ProfileModulePage? { modulesCache[key] }

    func profile(_ identity: ProfileIdentity, handleHint: String?) async throws -> ModulaProfile {
        let handle: String
        switch identity {
        case .me:
            if let handleHint, !handleHint.isEmpty {
                handle = handleHint
            } else {
                let me: JSONValue = try await client.authenticatedJSON("GET", path: "/v1/accounts/me")
                guard let resolved = me["primaryHandle"]?.string ?? me["handle"]?.string else {
                    throw APIError.invalidResponse
                }
                handle = resolved
            }
        case .handle(let value):
            handle = value
        case .id(let id):
            // Prefer handle hint; seed ids often 404 on /profiles/:handle.
            if let handleHint, !handleHint.isEmpty {
                handle = handleHint
            } else {
                handle = id
            }
        }
        do {
            let value = try await client.json("GET", path: "/v1/profiles/\(Self.pathEscaped(handle))")
            guard let profile = ProfilePayloadDecoder.profile(from: value) else {
                throw APIError.invalidResponse
            }
            profileCache[cacheKey(identity, handle: handle)] = profile
            profileCache[profile.routeID] = profile
            profileCache[profile.id] = profile
            return profile
        } catch let api as APIError {
            if case .rejected(_, let code) = api, code == "NOT_FOUND" {
                throw ProfileRepositoryError.notFound
            }
            throw api
        }
    }

    func posts(_ identity: ProfileIdentity, handle: String, cursor: String?) async throws -> ProfilePostPage {
        var path = "/v1/profiles/\(Self.pathEscaped(handle))/posts?limit=20"
        if let cursor, let encoded = Self.queryEscaped(cursor) {
            path += "&cursor=\(encoded)"
        }
        let value = try await client.json("GET", path: path)
        let page = ProfilePayloadDecoder.postPage(from: value)
        let key = cacheKey(identity, handle: handle)
        if cursor == nil {
            postsCache[key] = page
        } else if var existing = postsCache[key] {
            let seen = Set(existing.items.map(\.id))
            existing.items.append(contentsOf: page.items.filter { !seen.contains($0.id) })
            existing.nextCursor = page.nextCursor
            existing.hasMore = page.hasMore
            postsCache[key] = existing
        }
        return page
    }

    func modules(featuredIDs: [String], catalogue: [CatalogueProduct]) async -> ProfileModulePage {
        let key = featuredIDs.joined(separator: ",")
        var resolved: [CatalogueProduct] = []
        var seen = Set<String>()
        for id in featuredIDs {
            if let product = resolve(featuredID: id, in: catalogue), !seen.contains(product.moduleId) {
                resolved.append(product)
                seen.insert(product.moduleId)
            }
        }
        let page = ProfileModulePage(items: resolved, nextCursor: nil, hasMore: false)
        modulesCache[key] = page
        return page
    }

    func followers(handle: String, cursor: String?) async throws -> ProfilePeoplePage {
        try await people(
            path: "/v1/profiles/\(Self.pathEscaped(handle))/followers",
            handle: handle,
            cursor: cursor,
            cache: .followers
        )
    }

    func following(handle: String, cursor: String?) async throws -> ProfilePeoplePage {
        try await people(
            path: "/v1/profiles/\(Self.pathEscaped(handle))/following",
            handle: handle,
            cursor: cursor,
            cache: .following
        )
    }

    func follow(profileID: ProfileID, handle: String) async throws -> ModulaProfile {
        try await mutateFollow(profileID: profileID, handle: handle, method: "POST")
    }

    func unfollow(profileID: ProfileID, handle: String) async throws -> ModulaProfile {
        try await mutateFollow(profileID: profileID, handle: handle, method: "DELETE")
    }

    func block(profileID: ProfileID) async throws {
        let _: JSONValue = try await client.authenticatedJSON(
            "POST",
            path: "/v1/profiles/\(Self.pathEscaped(profileID))/block",
            body: .object([:])
        )
    }

    func unblock(profileID: ProfileID) async throws {
        let _: JSONValue = try await client.authenticatedJSON(
            "DELETE",
            path: "/v1/profiles/\(Self.pathEscaped(profileID))/block",
            body: nil
        )
    }

    func mute(profileID: ProfileID) async throws {
        let _: JSONValue = try await client.authenticatedJSON(
            "POST",
            path: "/v1/profiles/\(Self.pathEscaped(profileID))/mute",
            body: .object([:])
        )
    }

    func unmute(profileID: ProfileID) async throws {
        let _: JSONValue = try await client.authenticatedJSON(
            "DELETE",
            path: "/v1/profiles/\(Self.pathEscaped(profileID))/mute",
            body: nil
        )
    }

    func report(profileID: ProfileID, category: String, details: String?) async throws {
        var body: [String: JSONValue] = [
            "targetType": .string("profile"),
            "targetId": .string(profileID),
            "category": .string(category)
        ]
        if let details, !details.isEmpty {
            body["details"] = .string(details)
        }
        let _: JSONValue = try await client.authenticatedJSON(
            "POST",
            path: "/v1/reports",
            body: .object(body)
        )
    }

    func updateMe(_ draft: ProfileEditDraft) async throws -> ModulaProfile {
        var body: [String: JSONValue] = [
            "displayName": .string(draft.displayName),
            "bio": .string(draft.bio),
            "visibility": .string(draft.visibility.rawValue)
        ]
        if let version = draft.expectedVersion {
            body["expectedVersion"] = .number(Double(version))
        }
        let value: JSONValue = try await client.authenticatedJSON(
            "PATCH",
            path: "/v1/profiles/me",
            body: .object(body)
        )
        guard let profile = ProfilePayloadDecoder.profile(from: value) else {
            throw APIError.invalidResponse
        }
        profileCache["me"] = profile
        profileCache[profile.routeID] = profile
        profileCache[profile.id] = profile
        return profile
    }

    // MARK: - Private

    private enum PeopleCache {
        case followers
        case following
    }

    private func people(
        path base: String,
        handle: String,
        cursor: String?,
        cache: PeopleCache
    ) async throws -> ProfilePeoplePage {
        var path = "\(base)?limit=30"
        if let cursor, let encoded = Self.queryEscaped(cursor) {
            path += "&cursor=\(encoded)"
        }
        let value = try await client.json("GET", path: path)
        let page = ProfilePayloadDecoder.peoplePage(from: value)
        switch cache {
        case .followers:
            store(page, in: &followersCache, handle: handle, cursor: cursor)
        case .following:
            store(page, in: &followingCache, handle: handle, cursor: cursor)
        }
        return page
    }

    private func store(
        _ page: ProfilePeoplePage,
        in cache: inout [String: ProfilePeoplePage],
        handle: String,
        cursor: String?
    ) {
        if cursor == nil {
            cache[handle] = page
        } else if var existing = cache[handle] {
            let seen = Set(existing.items.map(\.id))
            existing.items.append(contentsOf: page.items.filter { !seen.contains($0.id) })
            existing.nextCursor = page.nextCursor
            existing.hasMore = page.hasMore
            cache[handle] = existing
        }
    }

    private func mutateFollow(profileID: ProfileID, handle: String, method: String) async throws -> ModulaProfile {
        do {
            let value: JSONValue = try await client.authenticatedJSON(
                method,
                path: "/v1/profiles/\(Self.pathEscaped(profileID))/follow",
                body: method == "DELETE" ? nil : .object([:])
            )
            if let profile = ProfilePayloadDecoder.profile(from: value["profile"] ?? value) {
                profileCache[profile.routeID] = profile
                profileCache[profile.id] = profile
                return profile
            }
        } catch {
            if handle == profileID { throw error }
            let value: JSONValue = try await client.authenticatedJSON(
                method,
                path: "/v1/profiles/\(Self.pathEscaped(handle))/follow",
                body: method == "DELETE" ? nil : .object([:])
            )
            if let profile = ProfilePayloadDecoder.profile(from: value["profile"] ?? value) {
                profileCache[profile.routeID] = profile
                profileCache[profile.id] = profile
                return profile
            }
            throw error
        }
        // Fallback: refetch
        return try await profile(.handle(handle), handleHint: handle)
    }

    private func resolve(featuredID: String, in catalogue: [CatalogueProduct]) -> CatalogueProduct? {
        if let exact = catalogue.first(where: { $0.moduleId == featuredID }) { return exact }
        if let named = catalogue.first(where: { $0.name.caseInsensitiveCompare(featuredID) == .orderedSame }) {
            return named
        }
        let slug = featuredID.replacingOccurrences(of: "module-", with: "")
        return catalogue.first(where: { $0.moduleId.contains(slug) || $0.name.lowercased().contains(slug) })
    }

    private func cacheKey(_ identity: ProfileIdentity, handle: String) -> String {
        switch identity {
        case .me: "me:\(handle)"
        case .handle(let value): value
        case .id(let id): id
        }
    }

    nonisolated static func pathEscaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? value
    }

    nonisolated static func queryEscaped(_ value: String) -> String? {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~")))
    }
}

enum ProfileRepositoryError: Error, Equatable {
    case notFound
    case unavailable
}
