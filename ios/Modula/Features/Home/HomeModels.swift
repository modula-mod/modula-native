import Foundation

enum HomeLoadState: Equatable {
    case idle
    case loading
    case loaded
    case refreshing
    case loadingMore
    case failed(String)
}

struct HomeModeState: Equatable {
    var items: [SocialPost] = []
    var nextCursor: String?
    var hasMore = false
    var loadState: HomeLoadState = .idle
    var lastRefresh: Date?
    var lastError: String?
    var rankingVersion: String?
    var scrollAnchor: String?
    var newerAvailable = false
}

extension HomeMode {
    /// Query value for `GET /v1/feed/home?mode=`.
    var apiQueryValue: String {
        switch self {
        case .following: "following"
        case .forYou: "forYou"
        case .modules: "modules"
        }
    }

    var heroTitle: String {
        switch self {
        case .following: "Your people, in focus."
        case .forYou: "More of what matters."
        case .modules: "Your tools, in motion."
        }
    }

    var heroSubtitle: String {
        switch self {
        case .following: "Following"
        case .forYou: "For You"
        case .modules: "Modules"
        }
    }

    var requiresAuth: Bool { self == .following }
}
