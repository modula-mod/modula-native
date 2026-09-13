import Foundation

enum AppTab: String, CaseIterable, Codable, Hashable, Identifiable {
    case home, discover, modules, activity, profile
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .home: "house"
        case .discover: "safari"
        case .modules: "shippingbox"
        case .activity: "bell"
        case .profile: "person.crop.circle"
        }
    }
    var selectedIcon: String {
        switch self {
        case .home: "house.fill"
        case .discover: "safari.fill"
        case .modules: "shippingbox.fill"
        case .activity: "bell.fill"
        case .profile: "person.crop.circle.fill"
        }
    }
    var defaultRoute: AppRoute {
        switch self {
        case .home: .home(.following)
        case .discover: .discover(.trending)
        case .modules: .productHub(.featured)
        case .activity: .activity(.all)
        case .profile: .me(.overview)
        }
    }
}

enum HomeMode: String, CaseIterable, Codable, Hashable { case following, forYou = "for-you", modules }
enum DiscoverRoute: String, CaseIterable, Codable, Hashable { case trending, people, topics, posts, modules }
enum SearchSection: String, CaseIterable, Codable, Hashable { case people, posts, modules, topics }
enum ActivityMode: String, CaseIterable, Codable, Hashable { case all, mentions, requests }
enum ProfileSection: String, CaseIterable, Codable, Hashable { case overview, posts, modules, followers, following, connections, links, edit }
enum ComposeRoute: String, CaseIterable, Codable, Hashable { case post, photo, video, link, poll, carousel, audio, movie }
enum PostSection: String, CaseIterable, Codable, Hashable { case root, comments, likes, reactions, shares, edit }
enum AuthRoute: String, CaseIterable, Codable, Hashable { case root, login, register, verify, forgotPassword = "forgot-password", resetPassword = "reset-password", welcome }
enum ModuleDetailSection: String, CaseIterable, Codable, Hashable {
    case overview, whatsNew = "whats-new", permissions, privacy, information, screenshots
    case versionHistory = "version-history", compatibility, publisher, support, configure
}
enum ProductHubCollection: String, CaseIterable, Codable, Hashable {
    case featured, modules, tools, functions, plugins, connections, widgets, installed, updates, comingSoon = "coming-soon", developer
}
enum ProductHubRoute: Hashable {
    case collection(ProductHubCollection)
    case category(String)
    case publisher(String)
    case search(String?)
    case module(String, ModuleDetailSection)
    static let featured = Self.collection(.featured)
}

enum AccountSettingsRoute: String, CaseIterable, Codable, Hashable {
    case root, personalInformation = "personal-information", username, email, password, sessions, deleteAccount = "delete-account"
}
enum AppearanceSettingsRoute: String, CaseIterable, Codable, Hashable {
    case root, theme, darkStyle = "dark-style", accent, typography, fontFamily = "font-family", textSize = "text-size"
    case appIcon = "app-icon", density, motion, haptics, contrastTransparency = "contrast-transparency"
    case iconStyle = "icon-style", interfaceShape = "interface-shape", moduleBranding = "module-branding", preview
}
enum NotificationSettingsRoute: String, CaseIterable, Codable, Hashable { case root, push, social, modules, quietHours = "quiet-hours" }
enum PrivacySettingsRoute: String, CaseIterable, Codable, Hashable { case root, privacy, security, glassPrivacy = "glass-privacy", blocked, appLock = "app-lock", biometrics }
enum DataSettingsRoute: String, CaseIterable, Codable, Hashable { case root, storage, cache, downloads, backup, export }
enum AccessibilitySettingsRoute: String, CaseIterable, Codable, Hashable { case root, text, contrast, motion }
enum FeatureSettingsRoute: String, CaseIterable, Codable, Hashable { case root, enabled, experimental }
enum UpdateSettingsRoute: String, CaseIterable, Codable, Hashable { case root, channel, stable, unstable, versionLock = "version-lock" }
enum DeveloperSettingsRoute: String, CaseIterable, Codable, Hashable { case root, runtime, modules, network, featureFlags = "feature-flags", environment, components, diagnostics }
enum AboutSettingsRoute: String, CaseIterable, Codable, Hashable { case root, version, licenses, privacy, terms }
enum ModuleSettingsSection: String, CaseIterable, Codable, Hashable { case general, permissions, data, updates, diagnostics, about }
enum ModuleSettingsRoute: Hashable {
    case root, installed, updates, autoUpdates, permissions
    case module(String, ModuleSettingsSection)
}
enum SettingsRoute: Hashable {
    case root
    case account(AccountSettingsRoute)
    case appearance(AppearanceSettingsRoute)
    case notifications(NotificationSettingsRoute)
    case privacy(PrivacySettingsRoute)
    case modules(ModuleSettingsRoute)
    case dataStorage(DataSettingsRoute)
    case accessibility(AccessibilitySettingsRoute)
    case features(FeatureSettingsRoute)
    case updates(UpdateSettingsRoute)
    case developer(DeveloperSettingsRoute)
    case about(AboutSettingsRoute)
}
enum MessagesRoute: Hashable { case root, new, conversation(String) }
enum TeamsRoute: Hashable { case root, create, team(String, TeamSection) }
enum TeamSection: String, CaseIterable, Codable, Hashable { case overview, members, roles, modules, settings }
enum DeveloperRoute: String, CaseIterable, Codable, Hashable { case components, appearance, modules, runtime, bridge, diagnostics }
enum SearchRoute: Hashable { case root(String?), section(SearchSection, String?) }

enum AppRoute: Hashable {
    case boot
    case auth(AuthRoute)
    case home(HomeMode)
    case discover(DiscoverRoute)
    case search(SearchRoute)
    case post(String, PostSection)
    case compose(ComposeRoute)
    case activity(ActivityMode)
    case notification(String?)
    case profile(String, ProfileSection)
    case me(ProfileSection)
    case productHub(ProductHubRoute)
    case module(String, localPath: String?)
    case settings(SettingsRoute)
    case messages(MessagesRoute)
    case teams(TeamsRoute)
    case developer(DeveloperRoute)

    var tab: AppTab? {
        switch self {
        case .home: .home
        case .discover, .search: .discover
        case .productHub, .module: .modules
        case .activity, .notification: .activity
        case .profile, .me: .profile
        default: nil
        }
    }
}

enum RouteRegistry {
    static let globalTabs = AppTab.allCases
    static func canonicalPath(for route: AppRoute) -> String { RouteSerializer.serialize(route) }
    static func parse(_ value: String) -> AppRoute? { RouteParser.parse(value) }
}

enum RouteParser {
    static func parse(_ value: String) -> AppRoute? {
        guard let normalized = normalize(value) else { return nil }
        let p = normalized.parts
        let q = normalized.query
        if p.isEmpty { return .boot }
        switch p[0] {
        case "auth":
            guard p.count <= 2 else { return nil }
            if p.count == 1 { return .auth(.root) }
            return AuthRoute(rawValue: p[1]).map(AppRoute.auth)
        case "home":
            guard p.count <= 2 else { return nil }
            if p.count == 1 { return .home(.following) }
            return HomeMode(rawValue: p[1]).map(AppRoute.home)
        case "discover":
            guard p.count <= 2 else { return nil }
            if p.count == 1 { return .discover(.trending) }
            return DiscoverRoute(rawValue: p[1]).map(AppRoute.discover)
        case "search":
            guard p.count <= 2 else { return nil }
            let query = q["q"]
            if p.count == 1 { return .search(.root(query)) }
            guard let section = SearchSection(rawValue: p[1]) else { return nil }
            return .search(.section(section, query))
        case "post":
            guard p.count == 2 || p.count == 3, validID(p[1]) else { return nil }
            let section = p.count == 2 ? PostSection.root : PostSection(rawValue: p[2])
            return section.map { .post(p[1], $0) }
        case "compose":
            guard p.count == 2, let route = ComposeRoute(rawValue: p[1]) else { return nil }
            return .compose(route)
        case "activity":
            guard p.count <= 2 else { return nil }
            if p.count == 1 { return .activity(.all) }
            return ActivityMode(rawValue: p[1]).map(AppRoute.activity)
        case "notifications":
            guard p.count <= 2, p.count == 1 || validID(p[1]) else { return nil }
            return .notification(p.count == 2 ? p[1] : nil)
        case "profile":
            guard p.count == 2 || p.count == 3, validID(p[1]) else { return nil }
            let section = p.count == 2 ? ProfileSection.overview : ProfileSection(rawValue: p[2])
            return section.map { .profile(p[1], $0) }
        case "me":
            guard p.count <= 2 else { return nil }
            if p.count == 1 { return .me(.overview) }
            return ProfileSection(rawValue: p[1]).map(AppRoute.me)
        case "product-hub": return parseProductHub(p, query: q)
        case "module":
            guard p.count >= 2, validID(p[1]), p.dropFirst(2).allSatisfy(validSegment) else { return nil }
            let local = p.count > 2 ? "/" + p.dropFirst(2).joined(separator: "/") : nil
            return .module(p[1], localPath: local)
        case "settings": return parseSettings(p)
        case "messages":
            guard p.count <= 2 else { return nil }
            if p.count == 1 { return .messages(.root) }
            if p[1] == "new" { return .messages(.new) }
            return validID(p[1]) ? .messages(.conversation(p[1])) : nil
        case "teams":
            guard p.count <= 3 else { return nil }
            if p.count == 1 { return .teams(.root) }
            if p[1] == "create" && p.count == 2 { return .teams(.create) }
            guard validID(p[1]) else { return nil }
            let section = p.count == 2 ? TeamSection.overview : TeamSection(rawValue: p[2])
            return section.map { .teams(.team(p[1], $0)) }
        case "developer":
            guard p.count == 2, let route = DeveloperRoute(rawValue: p[1]) else { return nil }
            return .developer(route)
        default: return nil
        }
    }

    private static func parseProductHub(_ p: [String], query: [String: String]) -> AppRoute? {
        if p.count == 1 { return .productHub(.featured) }
        if p[1] == "category", p.count == 3, validID(p[2]) { return .productHub(.category(p[2])) }
        if p[1] == "publisher", p.count == 3, validID(p[2]) { return .productHub(.publisher(p[2])) }
        if p[1] == "search", p.count == 2 { return .productHub(.search(query["q"])) }
        if p[1] == "module", p.count == 3 || p.count == 4, validID(p[2]) {
            let section = p.count == 3 ? ModuleDetailSection.overview : ModuleDetailSection(rawValue: p[3])
            return section.map { .productHub(.module(p[2], $0)) }
        }
        guard p.count == 2, let collection = ProductHubCollection(rawValue: p[1]) else { return nil }
        return .productHub(.collection(collection))
    }

    private static func parseSettings(_ p: [String]) -> AppRoute? {
        if p.count == 1 { return .settings(.root) }
        let tail = p.count > 2 ? p[2] : "root"
        switch p[1] {
        case "account": return AccountSettingsRoute(rawValue: tail).map { .settings(.account($0)) }
        case "appearance":
            if p.count == 4, p[2] == "typography" { return AppearanceSettingsRoute(rawValue: p[3]).map { .settings(.appearance($0)) } }
            return AppearanceSettingsRoute(rawValue: tail).map { .settings(.appearance($0)) }
        case "notifications": return NotificationSettingsRoute(rawValue: tail).map { .settings(.notifications($0)) }
        case "privacy-security": return PrivacySettingsRoute(rawValue: tail).map { .settings(.privacy($0)) }
        case "modules":
            if p.count == 2 { return .settings(.modules(.root)) }
            if p.count == 3 {
                switch p[2] {
                case "installed": return .settings(.modules(.installed))
                case "updates": return .settings(.modules(.updates))
                case "auto-updates": return .settings(.modules(.autoUpdates))
                case "permissions": return .settings(.modules(.permissions))
                default: return validID(p[2]) ? .settings(.modules(.module(p[2], .general))) : nil
                }
            }
            guard p.count == 4, validID(p[2]), let section = ModuleSettingsSection(rawValue: p[3]) else { return nil }
            return .settings(.modules(.module(p[2], section)))
        case "data-storage": return DataSettingsRoute(rawValue: tail).map { .settings(.dataStorage($0)) }
        case "accessibility": return AccessibilitySettingsRoute(rawValue: tail).map { .settings(.accessibility($0)) }
        case "features": return FeatureSettingsRoute(rawValue: tail).map { .settings(.features($0)) }
        case "updates":
            guard p.count <= 4 else { return nil }
            if p.count == 4, p[2] == "channel" { return UpdateSettingsRoute(rawValue: p[3]).map { .settings(.updates($0)) } }
            return UpdateSettingsRoute(rawValue: tail).map { .settings(.updates($0)) }
        case "developer": return DeveloperSettingsRoute(rawValue: tail).map { .settings(.developer($0)) }
        case "about": return AboutSettingsRoute(rawValue: tail).map { .settings(.about($0)) }
        default: return nil
        }
    }

    private static func normalize(_ value: String) -> (parts: [String], query: [String: String])? {
        guard !value.isEmpty, value.count <= 2_048 else { return nil }
        let unsafe = value.lowercased()
        guard !unsafe.contains("/../"), !unsafe.hasSuffix("/.."), !unsafe.contains("%2f"), !unsafe.contains("%5c"), !unsafe.contains("%2e%2e") else { return nil }
        let components: URLComponents?
        if value.contains("://") {
            guard let url = URLComponents(string: value), let scheme = url.scheme?.lowercased() else { return nil }
            if scheme == "https" {
                guard url.host?.lowercased() == "modula.digital" else { return nil }
                components = url
            } else if scheme == "modula" {
                var rebuilt = URLComponents()
                rebuilt.path = (url.host.map { "/" + $0 } ?? "") + url.path
                rebuilt.queryItems = url.queryItems
                components = rebuilt
            } else { return nil }
        } else { components = URLComponents(string: value.hasPrefix("/") ? value : "/" + value) }
        guard let components else { return nil }
        guard !components.percentEncodedPath.contains("//") else { return nil }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.allSatisfy(validSegment) else { return nil }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] where item.name == "q" {
            if let value = item.value, value.count <= 256 { query[item.name] = value }
        }
        return (parts, query)
    }

    static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 160 && value != "." && value != ".." &&
        value.range(of: "^[A-Za-z0-9._:-]+$", options: .regularExpression) != nil
    }
    private static func validSegment(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 160 && value != "." && value != ".." &&
        value.range(of: "^[A-Za-z0-9._~:-]+$", options: .regularExpression) != nil
    }
}

enum RouteSerializer {
    static func serialize(_ route: AppRoute) -> String {
        switch route {
        case .boot: "/"
        case .auth(let r): path("auth", r.rawValue == "root" ? nil : r.rawValue)
        case .home(let mode): path("home", mode.rawValue)
        case .discover(let route): path("discover", route.rawValue)
        case .search(let route):
            switch route { case .root(let q): queryPath("/search", q); case .section(let section, let q): queryPath("/search/\(section.rawValue)", q) }
        case .post(let id, let section): path("post", id, section == .root ? nil : section.rawValue)
        case .compose(let route): path("compose", route.rawValue)
        case .activity(let mode): path("activity", mode.rawValue)
        case .notification(let id): path("notifications", id)
        case .profile(let id, let section): path("profile", id, section.rawValue)
        case .me(let section): path("me", section == .overview ? nil : section.rawValue)
        case .productHub(let route): productHub(route)
        case .module(let id, let local): "/module/\(id)\(local ?? "")"
        case .settings(let route): settings(route)
        case .messages(let route):
            switch route { case .root: "/messages"; case .new: "/messages/new"; case .conversation(let id): "/messages/\(id)" }
        case .teams(let route):
            switch route { case .root: "/teams"; case .create: "/teams/create"; case .team(let id, let section): path("teams", id, section.rawValue) }
        case .developer(let route): path("developer", route.rawValue)
        }
    }
    private static func productHub(_ route: ProductHubRoute) -> String {
        switch route {
        case .collection(let section): path("product-hub", section.rawValue)
        case .category(let id): path("product-hub", "category", id)
        case .publisher(let id): path("product-hub", "publisher", id)
        case .search(let q): queryPath("/product-hub/search", q)
        case .module(let id, let section): path("product-hub", "module", id, section == .overview ? nil : section.rawValue)
        }
    }
    private static func settings(_ route: SettingsRoute) -> String {
        switch route {
        case .root: "/settings"
        case .account(let r): setting("account", r.rawValue)
        case .appearance(let r):
            if r == .fontFamily || r == .textSize { path("settings", "appearance", "typography", r.rawValue) }
            else { setting("appearance", r.rawValue) }
        case .notifications(let r): setting("notifications", r.rawValue)
        case .privacy(let r): setting("privacy-security", r.rawValue)
        case .modules(let r):
            switch r {
            case .root: "/settings/modules"
            case .installed: "/settings/modules/installed"
            case .updates: "/settings/modules/updates"
            case .autoUpdates: "/settings/modules/auto-updates"
            case .permissions: "/settings/modules/permissions"
            case .module(let id, let section): path("settings", "modules", id, section == .general ? nil : section.rawValue)
            }
        case .dataStorage(let r): setting("data-storage", r.rawValue)
        case .accessibility(let r): setting("accessibility", r.rawValue)
        case .features(let r): setting("features", r.rawValue)
        case .updates(let r):
            if r == .stable || r == .unstable { path("settings", "updates", "channel", r.rawValue) }
            else { setting("updates", r.rawValue) }
        case .developer(let r): setting("developer", r.rawValue)
        case .about(let r): setting("about", r.rawValue)
        }
    }
    private static func setting(_ root: String, _ raw: String) -> String { path("settings", root, raw == "root" ? nil : raw) }
    private static func queryPath(_ path: String, _ query: String?) -> String {
        guard let query, !query.isEmpty else { return path }
        var components = URLComponents(); components.path = path; components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.string ?? path
    }
    private static func path(_ values: String?...) -> String { "/" + values.compactMap { $0 }.joined(separator: "/") }
}
