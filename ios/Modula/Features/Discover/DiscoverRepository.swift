import Foundation

protocol DiscoverRepository: Sendable {
    func dashboard() async throws -> DiscoverDashboard
    func people(cursor: String?) async throws -> PeoplePage
    func topics(cursor: String?) async throws -> TopicsPage
    func posts(cursor: String?) async throws -> PostsPage
    func modules(cursor: String?) async throws -> ModulesPage
    func search(query: String, entityType: String?, cursor: String?) async throws -> SearchPage
    func follow(person: DiscoverPerson) async throws
    func unfollow(person: DiscoverPerson) async throws
}

actor GreenfieldDiscoverRepository: DiscoverRepository {
    private let client: GreenfieldClient
    private var dashboardCache: DiscoverDashboard?
    private var peopleCache: PeoplePage?
    private var topicsCache: TopicsPage?
    private var postsCache: PostsPage?
    private var modulesCache: ModulesPage?
    private var searchCache: [String: SearchPage] = [:]

    init(client: GreenfieldClient) {
        self.client = client
    }

    func cachedDashboard() -> DiscoverDashboard? { dashboardCache }
    func cachedPeople() -> PeoplePage? { peopleCache }
    func cachedTopics() -> TopicsPage? { topicsCache }
    func cachedPosts() -> PostsPage? { postsCache }
    func cachedModules() -> ModulesPage? { modulesCache }

    func dashboard() async throws -> DiscoverDashboard {
        let value = try await client.json("GET", path: "/v1/discover")
        let page = DiscoverPayloadDecoder.dashboard(from: value)
        dashboardCache = page
        if peopleCache == nil {
            peopleCache = PeoplePage(items: ranked(page.people), nextCursor: nil)
        }
        if topicsCache == nil {
            topicsCache = TopicsPage(items: page.topics, nextCursor: nil)
        }
        return page
    }

    func people(cursor _: String?) async throws -> PeoplePage {
        let dash = try await dashboard()
        let page = PeoplePage(items: ranked(dash.people), nextCursor: nil)
        peopleCache = page
        return page
    }

    func topics(cursor _: String?) async throws -> TopicsPage {
        let dash = try await dashboard()
        let page = TopicsPage(items: dash.topics, nextCursor: nil)
        topicsCache = page
        return page
    }

    func posts(cursor: String?) async throws -> PostsPage {
        if let cursor {
            let parts = cursor.split(separator: "\u{1e}", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let more = try await profilePosts(handle: parts[0], cursor: parts[1].isEmpty ? nil : parts[1])
                var merged = postsCache ?? PostsPage(items: [], nextCursor: nil)
                let existing = Set(merged.items.map(\.id))
                merged.items.append(contentsOf: more.items.filter { !existing.contains($0.id) })
                let composed = more.nextCursor.map { "\(parts[0])\u{1e}\($0)" } ?? nextAuthorCursor(after: parts[0])
                merged.nextCursor = composed
                postsCache = merged
                return PostsPage(items: more.items, nextCursor: composed)
            }
        }

        let dash = try await dashboard()
        let authors = ranked(dash.people).filter { ($0.postCount ?? 0) > 0 }
        var collected: [DiscoverPost] = []
        var next: String?
        for (index, author) in authors.prefix(6).enumerated() {
            let page = try await profilePosts(handle: author.handle, cursor: nil)
            collected.append(contentsOf: page.items)
            if collected.count >= 8 {
                if let more = page.nextCursor {
                    next = "\(author.handle)\u{1e}\(more)"
                } else if index + 1 < authors.count {
                    next = "\(authors[index + 1].handle)\u{1e}"
                }
                break
            }
            if index == authors.prefix(6).count - 1, index + 1 < authors.count {
                next = "\(authors[index + 1].handle)\u{1e}"
            }
        }
        let page = PostsPage(items: collected, nextCursor: next)
        postsCache = page
        return page
    }

    func modules(cursor: String?) async throws -> ModulesPage {
        var path = "/v1/registry/products?limit=50"
        if let cursor, let encoded = Self.queryEscaped(cursor) {
            path += "&cursor=\(encoded)"
        }
        let value = try await client.json("GET", path: path)
        let items = (value["items"]?.array ?? value.array ?? []).compactMap(Self.decodeProduct)
        let next = value["nextCursor"]?.string ?? value["next_cursor"]?.string
        let page = ModulesPage(items: items, nextCursor: next)
        if cursor == nil { modulesCache = page }
        return page
    }

    func search(query: String, entityType: String?, cursor: String?) async throws -> SearchPage {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SearchPage(results: [], nextCursor: nil) }
        var params = "q=\(Self.queryEscaped(trimmed) ?? trimmed)&limit=20"
        if let entityType, !entityType.isEmpty, let encoded = Self.queryEscaped(entityType) {
            params += "&entityType=\(encoded)"
        }
        if let cursor, let encoded = Self.queryEscaped(cursor) {
            params += "&cursor=\(encoded)"
        }
        let value = try await client.json("GET", path: "/v1/search?\(params)")
        let page = DiscoverPayloadDecoder.searchPage(from: value)
        if cursor == nil { searchCache[cacheKey(query: trimmed, entityType: entityType)] = page }
        return page
    }

    func follow(person: DiscoverPerson) async throws {
        try await mutateFollow(person: person, method: "POST")
    }

    func unfollow(person: DiscoverPerson) async throws {
        try await mutateFollow(person: person, method: "DELETE")
    }

    // MARK: - Private

    private func profilePosts(handle: String, cursor: String?) async throws -> PostsPage {
        var path = "/v1/profiles/\(Self.pathEscaped(handle))/posts?limit=8"
        if let cursor, let encoded = Self.queryEscaped(cursor) {
            path += "&cursor=\(encoded)"
        }
        let value = try await client.json("GET", path: path)
        return DiscoverPayloadDecoder.postsPage(from: value)
    }

    private func mutateFollow(person: DiscoverPerson, method: String) async throws {
        do {
            let _: JSONValue = try await client.authenticatedJSON(
                method,
                path: "/v1/profiles/\(Self.pathEscaped(person.id))/follow",
                body: method == "DELETE" ? nil : .object([:])
            )
        } catch {
            guard person.handle != person.id else { throw error }
            let _: JSONValue = try await client.authenticatedJSON(
                method,
                path: "/v1/profiles/\(Self.pathEscaped(person.handle))/follow",
                body: method == "DELETE" ? nil : .object([:])
            )
        }
    }

    private func ranked(_ people: [DiscoverPerson]) -> [DiscoverPerson] {
        people.sorted { lhs, rhs in
            if lhs.usefulness != rhs.usefulness { return lhs.usefulness > rhs.usefulness }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func nextAuthorCursor(after handle: String) -> String? {
        guard let people = dashboardCache?.people else { return nil }
        let authors = ranked(people).filter { ($0.postCount ?? 0) > 0 }
        guard let index = authors.firstIndex(where: { $0.handle == handle }), index + 1 < authors.count else { return nil }
        return "\(authors[index + 1].handle)\u{1e}"
    }

    private func cacheKey(query: String, entityType: String?) -> String {
        "\(entityType ?? "*")|\(query.lowercased())"
    }

    nonisolated static func pathEscaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? value
    }

    nonisolated static func queryEscaped(_ value: String) -> String? {
        value.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~")))
    }

    nonisolated static func resolve(_ featured: DiscoverFeaturedModule, in products: [CatalogueProduct]) -> CatalogueProduct? {
        if let exact = products.first(where: { $0.moduleId == featured.id || $0.moduleId == featured.catalogueID }) {
            return exact
        }
        if let named = products.first(where: { $0.name.caseInsensitiveCompare(featured.name) == .orderedSame }) {
            return named
        }
        let slug = featured.id.replacingOccurrences(of: "module-", with: "")
        return products.first(where: { $0.moduleId.contains(slug) })
    }

    nonisolated static func decodeProduct(_ value: JSONValue) -> CatalogueProduct? {
        guard let moduleId = value["moduleId"]?.string ?? value["module_id"]?.string else { return nil }
        let installability: CatalogueProduct.Installability?
        if let nested = value["installability"] {
            installability = CatalogueProduct.Installability(
                status: nested["status"]?.string ?? "",
                reasonCode: nested["reasonCode"]?.string,
                reason: nested["reason"]?.string
            )
        } else {
            installability = nil
        }
        return CatalogueProduct(
            moduleId: moduleId,
            productKind: value["productKind"]?.string ?? value["product_kind"]?.string ?? "module",
            name: value["name"]?.string ?? moduleId,
            description: value["description"]?.string ?? "",
            publisherId: value["publisherId"]?.string ?? value["publisher_id"]?.string ?? "",
            publisherName: value["publisherName"]?.string ?? value["publisher_name"]?.string ?? "",
            latestVersion: value["latestVersion"]?.string ?? value["latest_version"]?.string,
            status: value["status"]?.string ?? "",
            installable: value["installable"]?.bool ?? false,
            platforms: (value["platforms"]?.array ?? []).compactMap(\.string),
            betaClassification: value["betaClassification"]?.string,
            installability: installability,
            presentation: CataloguePresentation.from(value["presentation"])
        )
    }
}
