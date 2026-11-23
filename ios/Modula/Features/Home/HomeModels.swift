import Foundation

enum HomeLoadState: Equatable {
    case idle
    case loading
    case loaded
    case refreshing
    case loadingMore
    case failed(String)
}

struct HomeFeedDisplayOptions: Equatable, Codable, Sendable {
    var mediaOnly = false
    var hideModules = false
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
    /// Set when the next page failed. The list end stays visible so the user can retry —
    /// the row `onAppear` that normally pages won't fire again for rows already on screen.
    var loadMoreError: String?
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

/// Time-of-day greeting for the Home hero. The name comes from the signed-in profile;
/// the line and date are computed on device. Nothing here is a server metric.
enum HomeGreeting {
    static func line(for date: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        return switch hour {
        case 5..<12: "Good morning,"
        case 12..<17: "Good afternoon,"
        case 17..<22: "Good evening,"
        default: "Good night,"
        }
    }

    static func symbol(for date: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        return switch hour {
        case 5..<12: "sunrise.fill"
        case 12..<17: "sun.max.fill"
        case 17..<22: "sunset.fill"
        default: "moon.stars.fill"
        }
    }

    /// First token of the display name, otherwise the handle, otherwise a neutral greeting.
    static func name(displayName: String?, handle: String?) -> String {
        if let displayName {
            let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let first = trimmed.split(whereSeparator: \.isWhitespace).first, !first.isEmpty {
                return String(first)
            }
        }
        if let handle {
            let trimmed = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@").union(.whitespacesAndNewlines))
            if !trimmed.isEmpty { return trimmed }
        }
        return "there"
    }

    static func dateChip(_ date: Date, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter.string(from: date)
    }
}
