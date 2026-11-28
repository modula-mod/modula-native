import Foundation

/// Recently visited destinations for the sidebar ("Recent"), newest first. On this iPhone only:
/// there is no server route for navigation history. Stored as route paths so deep-link parsing
/// restores them; only destinations with a stable name are kept.
enum SpatialRecents {
    static let key = "spatial.recentDestinations"
    static let limit = 8

    struct Label: Equatable {
        var title: String
        var symbol: String
    }

    static func load(defaults: UserDefaults = .standard) -> [AppRoute] {
        (defaults.stringArray(forKey: key) ?? []).compactMap { RouteParser.parse($0) }
    }

    static func note(_ route: AppRoute, defaults: UserDefaults = .standard) {
        guard isRecordable(route) else { return }
        let path = RouteSerializer.serialize(route)
        var list = (defaults.stringArray(forKey: key) ?? []).filter { $0 != path }
        list.insert(path, at: 0)
        defaults.set(Array(list.prefix(limit)), forKey: key)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    static func isRecordable(_ route: AppRoute) -> Bool {
        if case .module = route { return true }
        return label(for: route) != nil
    }

    /// Name + SF Symbol for a recordable route. Modules are named from the catalogue by the caller.
    static func label(for route: AppRoute) -> Label? {
        switch route {
        case .saved: Label(title: "Saved", symbol: "bookmark")
        case .collections(.root): Label(title: "Collections", symbol: "rectangle.stack")
        case .drafts: Label(title: "Drafts", symbol: "doc.text")
        case .board: Label(title: "Board", symbol: "square.grid.2x2")
        case .messages(.inbox): Label(title: "Messages", symbol: "bubble.left.and.bubble.right")
        case .messages(.requests): Label(title: "Message requests", symbol: "tray")
        case .developer(.studio): Label(title: "Builder", symbol: "hammer")
        case .community: Label(title: "Community", symbol: "person.3")
        case .productHub(.featured): Label(title: "Product Hub", symbol: "shippingbox")
        case .settings(let settings):
            switch settings {
            case .root: Label(title: "Settings", symbol: "gearshape")
            case .appearance: Label(title: "Appearance", symbol: "paintpalette")
            case .moliboo: Label(title: "Moliboos", symbol: "sparkles")
            case .notifications: Label(title: "Notifications", symbol: "bell.badge")
            case .privacy: Label(title: "Privacy & Security", symbol: "lock.shield")
            case .developer(.nodus): Label(title: "Nodus", symbol: "brain")
            default: nil
            }
        default: nil
        }
    }
}
