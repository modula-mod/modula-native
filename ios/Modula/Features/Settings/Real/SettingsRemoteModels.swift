import Foundation

// Typed models for the settings endpoints added in settings-backend-v2.

struct AppPreferencesResponse: Decodable, Sendable, Equatable {
    struct Digests: Decodable, Sendable, Equatable {
        struct Delivery: Decodable, Sendable, Equatable, Identifiable {
            var id: String { "\(kind)-\(period)" }
            let kind: String
            let period: String
            let outcome: String
            let at: String
        }
        struct Schedule: Decodable, Sendable, Equatable {
            let morning: String
            let weekly: String
        }
        let deliveryEmail: String?
        let emailVerified: Bool
        let weeklyEnabled: Bool
        let morningEnabled: Bool
        let timeZone: String
        let schedule: Schedule
        let recent: [Delivery]
    }
    let preferences: [String: JSONValue]
    let version: Int
    let digests: Digests
}

struct RelationshipListResponse: Decodable, Sendable, Equatable {
    struct Item: Decodable, Sendable, Equatable, Identifiable {
        var id: String { profileId }
        let profileId: String
        let actorId: String
        let handle: String
        let displayName: String
        let avatarUrl: String?
        let since: String
    }
    let items: [Item]
}

struct CreatorInsightsResponse: Decodable, Sendable, Equatable {
    struct Totals: Decodable, Sendable, Equatable {
        let likes: Int, reactions: Int, comments: Int, shares: Int, saves: Int
        let newFollowers: Int, posts: Int, storyViews: Int, followers: Int
        var engagement: Int { likes + reactions + comments + shares + saves }
    }
    struct Point: Decodable, Sendable, Equatable, Identifiable {
        var id: String { date }
        let date: String
        let likes: Int, reactions: Int, comments: Int, shares: Int, saves: Int
        let newFollowers: Int, posts: Int, storyViews: Int
        var engagement: Int { likes + reactions + comments + shares + saves }
        var day: Date { CreatorInsightsResponse.dayFormatter.date(from: date) ?? .distantPast }
    }
    struct TopPost: Decodable, Sendable, Equatable, Identifiable {
        var id: String { postId }
        let postId: String
        let kind: String
        let excerpt: String
        let createdAt: String
        let likes: Int, reactions: Int, replies: Int, reposts: Int, shares: Int, saves: Int
        var interactions: Int { likes + reactions + replies + reposts + shares + saves }
    }
    let days: Int
    let generatedAt: String
    let totals: Totals
    let series: [Point]
    let topPosts: [TopPost]
    let notTracked: [String]

    nonisolated(unsafe) static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Change between the first and second half of the window, as a fraction. Nil when there's no baseline.
    nonisolated static func trend(_ values: [Int]) -> Double? {
        guard values.count >= 2 else { return nil }
        let half = values.count / 2
        let before = values.prefix(half).reduce(0, +)
        let after = values.suffix(values.count - half).reduce(0, +)
        guard before > 0 else { return nil }
        return Double(after - before) / Double(before)
    }
}

struct PayoutsLedgerResponse: Decodable, Sendable, Equatable {
    struct Balance: Decodable, Sendable, Equatable, Identifiable {
        var id: String { currency }
        let currency: String
        let amountMinor: Int
    }
    struct Entry: Decodable, Sendable, Equatable, Identifiable {
        var id: String { entryId }
        let entryId: String
        let kind: String
        let amountMinor: Int
        let currency: String
        let description: String
        let occurredAt: String
    }
    let provider: String?
    let payoutsEnabled: Bool
    let reason: String?
    let balances: [Balance]
    let entries: [Entry]
}

struct InvoicesResponse: Decodable, Sendable, Equatable {
    struct Invoice: Decodable, Sendable, Equatable, Identifiable {
        var id: String { invoiceId }
        let invoiceId: String
        let number: String
        let state: String
        let description: String
        let totalMinor: Int
        let currency: String
        let issuedAt: String
        let paidAt: String?
    }
    let provider: String?
    let items: [Invoice]
}

struct DeletionStatusResponse: Decodable, Sendable, Equatable {
    struct Request: Decodable, Sendable, Equatable {
        let requestId: String
        let state: String
        let requestedAt: String
        let scheduledFor: String?
        let cancellable: Bool
    }
    let request: Request?
    let gracePeriodDays: Int
}

enum SettingsMoney {
    /// Formats minor units (pence, cents) for a currency code.
    nonisolated static func format(minor: Int, currency: String, locale: Locale = .current) -> String {
        let digits = ["JPY", "KRW", "ISK"].contains(currency.uppercased()) ? 0 : 2
        let value = Decimal(minor) / pow(10, digits)
        return value.formatted(.currency(code: currency).locale(locale))
    }
}

enum SettingsISODate {
    nonisolated static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

enum SettingsRemoteError {
    /// Short, member-facing text for a failed settings request.
    nonisolated static func message(_ error: Error, fallback: String) -> String {
        if case APIError.rejected(_, let code) = error {
            switch code {
            case "RATE_LIMITED": return "Too many attempts. Try again in a few minutes."
            case "VALIDATION_FAILED": return "That didn’t look right. Check it and try again."
            case "STEP_UP_REQUIRED", "FORBIDDEN": return "Confirm it’s you first."
            case "CONFLICT": return "That can’t be done right now."
            case "UNAUTHENTICATED": return "Sign in again to continue."
            default: break
            }
        }
        return fallback
    }
}
