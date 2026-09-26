import Foundation

struct BraveDeveloperSearchProvider: NodusSearchProvider {
    let id = "brave.developer-search"
    let displayName = "Brave Search"
    private let apiKey: String
    private let session: URLSession
    private let endpoint: URL
    private let now: @Sendable () -> Date

    init(
        apiKey: String,
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.search.brave.com/res/v1/web/search")!,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.apiKey = apiKey
        self.session = session
        self.endpoint = endpoint
        self.now = now
    }

    func search(query: String, limit: Int = 6) async throws -> NodusSearchResponse {
        try Task.checkCancellation()
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 600, clean.split(whereSeparator: \.isWhitespace).count <= 75 else {
            throw NodusSearchError.invalidQuery
        }
        guard endpoint.scheme == "https", endpoint.host == "api.search.brave.com" || endpoint.isFileURL else {
            throw NodusSearchError.invalidResponse
        }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: clean),
            URLQueryItem(name: "count", value: String(min(max(limit, 1), 20))),
            URLQueryItem(name: "safesearch", value: "moderate"),
            URLQueryItem(name: "extra_snippets", value: "true"),
        ]
        guard let url = components?.url else { throw NodusSearchError.invalidQuery }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "X-Subscription-Token")
        request.setValue("ModulaNative/Nodus-02A", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw NodusSearchError.invalidResponse }
            guard (200 ..< 300).contains(http.statusCode) else { throw NodusSearchError.rejected }
            guard data.count <= 4_000_000 else { throw NodusSearchError.invalidResponse }
            let payload = try JSONDecoder().decode(BraveResponse.self, from: data)
            let retrievedAt = now()
            let results = payload.web?.results.prefix(min(max(limit, 1), 20)).compactMap { item -> NodusSearchResult? in
                guard let url = URL(string: item.url), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
                    return nil
                }
                let context = ((item.description.map { [$0] } ?? []) + (item.extraSnippets ?? []))
                    .filter { !$0.isEmpty }.joined(separator: " ")
                return NodusSearchResult(
                    title: item.title, url: url, snippet: context,
                    publishedAt: Self.parseDate(item.pageAge ?? item.age), retrievedAt: retrievedAt, provider: id
                )
            } ?? []
            return NodusSearchResponse(query: clean, results: results, retrievedAt: retrievedAt, provider: id)
        } catch is CancellationError {
            throw NodusSearchError.cancelled
        } catch let error as NodusSearchError {
            throw error
        } catch let error as URLError where [
            .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
            .dnsLookupFailed, .internationalRoamingOff,
        ].contains(error.code) {
            throw NodusSearchError.offline
        } catch {
            throw NodusSearchError.invalidResponse
        }
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }
}

private struct BraveResponse: Decodable {
    let web: Web?
    struct Web: Decodable { let results: [Result] }
    struct Result: Decodable {
        let title: String
        let url: String
        let description: String?
        let age: String?
        let pageAge: String?
        let extraSnippets: [String]?

        enum CodingKeys: String, CodingKey {
            case title, url, description, age
            case pageAge = "page_age"
            case extraSnippets = "extra_snippets"
        }
    }
}

#if DEBUG
struct FixtureNodusSearchProvider: NodusSearchProvider {
    let id = "modula.test.search"
    let displayName = "Search Fixture"
    let results: [NodusSearchResult]

    func search(query: String, limit: Int) async throws -> NodusSearchResponse {
        try Task.checkCancellation()
        return NodusSearchResponse(
            query: query, results: Array(results.prefix(limit)), retrievedAt: Date(), provider: id
        )
    }
}
#endif
