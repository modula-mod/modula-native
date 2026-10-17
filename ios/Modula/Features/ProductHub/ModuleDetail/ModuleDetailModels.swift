import Foundation

enum ModulePrimaryAction: Equatable, Sendable {
    case install
    case installing
    case open
    case update
    case updating
    case uninstalling
    case signIn
    case unavailable
    case incompatible
    case comingSoon

    var title: String {
        switch self {
        case .install: "Install"
        case .installing: "Installing"
        case .open: "Open"
        case .update: "Update"
        case .updating: "Updating"
        case .uninstalling: "Removing"
        case .signIn: "Sign in to install"
        case .unavailable: "Not on iOS yet"
        case .incompatible: "Incompatible"
        case .comingSoon: "Coming Soon"
        }
    }

    var isEnabled: Bool {
        switch self {
        case .open, .install, .update, .signIn: true
        default: false
        }
    }

    var isBusy: Bool { [.installing, .updating, .uninstalling].contains(self) }
}

/// One row of `GET /v1/modules/installed`. Only `enabled` installations can run: the
/// records API rejects every other state.
struct ModuleInstallation: Equatable, Hashable, Sendable {
    let moduleId: String
    let status: String
    let version: String?

    private static let gone: Set<String> = ["removed", "uninstalled", "notInstalled", "failed"]
    private static let transitioning: Set<String> = ["resolving", "permissionReview", "installing", "enabling", "updating", "uninstalling", "disabling"]

    var isPresent: Bool { !Self.gone.contains(status) }
    var isTransitioning: Bool { Self.transitioning.contains(status) }
    var isRunnable: Bool { status == "enabled" || status == "updateAvailable" }
    var needsEnable: Bool { status == "installedDisabled" || status == "disabled" }
}

/// What the store is doing locally for a module while the server settles.
enum ModuleOperation: Equatable, Sendable { case installing, updating, uninstalling }

enum ModuleVersion {
    /// Numeric dotted comparison ("1.10.0" > "1.9.2"); pre-release suffixes are ignored.
    static func isOlder(_ lhs: String, than rhs: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }
        let a = parts(lhs), b = parts(rhs)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x < y }
        }
        return false
    }
}

struct ModuleDetailPresentation: Equatable {
    var product: CatalogueProduct
    var installation: ModuleInstallation?
    var operation: ModuleOperation?
    /// Native code for this module ships in the app (bundled runtime entry).
    var bundled: Bool
    var bundledVersion: String?
    var signedIn: Bool = true

    var installed: Bool { installation?.isPresent == true }

    /// The store button. Install state comes from the server; "bundled" only means the
    /// app can run it — a bundled module still has to be installed for the account,
    /// because its records are scoped to the installation.
    var primaryAction: ModulePrimaryAction {
        switch operation {
        case .installing: return .installing
        case .updating: return .updating
        case .uninstalling: return .uninstalling
        case nil: break
        }
        let status = product.installability?.status.lowercased() ?? product.status.lowercased()
        if let installation, installation.isPresent {
            if installation.isTransitioning {
                switch installation.status {
                case "uninstalling": return .uninstalling
                case "updating": return .updating
                default: return .installing
                }
            }
            guard bundled else { return .unavailable }
            if updateAvailable { return .update }
            return .open
        }
        if status.contains("incompatible") { return .incompatible }
        if status.contains("coming") || !product.installable { return .comingSoon }
        guard bundled else { return .unavailable }
        return signedIn ? .install : .signIn
    }

    /// An update is offered when the registry has a newer release than the account's
    /// installation. Host compatibility is the registry's decision (`ModulaHost.version`),
    /// not a comparison with the bundled module code's version label.
    var updateAvailable: Bool {
        guard let current = installation?.version, let latest = product.latestVersion else { return false }
        return ModuleVersion.isOlder(current, than: latest)
    }

    var canUninstall: Bool { installed && operation == nil && installation?.isTransitioning == false }

    var tags: [String] {
        var values: [String] = []
        if !product.productKind.isEmpty { values.append(product.productKind.capitalized) }
        values.append(contentsOf: product.platforms.map { $0.uppercased() == "IOS" ? "iOS" : $0.capitalized })
        if product.installable { values.append("Installable") }
        return values
    }
}

/// Lenient view of `GET /v1/registry/modules/:id`. Every field is optional so a catalogue
/// that omits (or later adds) marketplace data never breaks the detail page.
struct ModuleListing: Equatable, Sendable {
    struct Permission: Equatable, Sendable, Identifiable {
        var id: String { permission }
        let permission: String
        let risk: String
        let reason: String
    }
    struct Preview: Equatable, Sendable, Identifiable {
        let id: String
        let source: URL
        let alt: String?
        let aspect: Double?
    }

    var moduleId: String
    var name: String?
    var description: String?
    var publisherName: String?
    var publisherWebsite: URL?
    var latestVersion: String?
    var trust: String?
    var category: String?
    var ageRating: String?
    var privacy: String?
    var offlineSupport: Bool?
    var syncSupport: Bool?
    var inAppPurchases: Bool?
    var ratingAverage: Double?
    var ratingCount: Int = 0
    var installCount: Int?
    var chartRank: Int?
    var chartCategory: String?
    var publishedAt: Date?
    var sizeBytes: Int?
    var releaseNotes: [String] = []
    var permissions: [Permission] = []
    var previews: [Preview] = []
    var platforms: [String] = []
    var minimumHostVersion: String?
    var iconURL: URL?
    var coverURL: URL?

    init?(json: JSONValue) {
        guard let id = json["moduleId"]?.string else { return nil }
        moduleId = id
        name = json["name"]?.string
        description = json["description"]?.string
        publisherName = json["publisher"]?["displayName"]?.string
        publisherWebsite = Self.https(json["publisher"]?["website"]?.string)
        latestVersion = json["latestVersion"]?.string
        trust = json["trust"]?.string
        let market = json["marketplace"]
        func declared(_ key: String) -> JSONValue? {
            guard let entry = market?[key], entry["state"]?.string != "undeclared" else { return nil }
            return entry["value"]
        }
        category = declared("category")?.string
        ageRating = declared("ageRating")?.string
        privacy = declared("privacy")?.string
        offlineSupport = declared("offlineSupport")?.bool
        syncSupport = declared("syncSupport")?.bool
        inAppPurchases = declared("inAppPurchases")?.bool
        ratingAverage = market?["rating"]?["average"]?.number
        ratingCount = market?["rating"]?["count"]?.int ?? 0
        installCount = market?["installations"]?["count"]?.int
        chartRank = market?["chart"]?["rank"]?.int
        chartCategory = market?["chart"]?["category"]?.string
        let release = market?["release"]
        publishedAt = Self.date(release?["publishedAt"]?.string ?? json["publishedAt"]?.string)
        sizeBytes = release?["sizeBytes"]?.int ?? json["releaseSizeBytes"]?.int
        let notes = (release?["notes"]?.array ?? json["releaseNotes"]?.array ?? []).compactMap(\.string)
        releaseNotes = Array(notes.prefix(20))
        permissions = (json["permissions"]?.array ?? []).prefix(50).compactMap { item in
            guard let name = item["permission"]?.string else { return nil }
            return Permission(permission: name, risk: item["risk"]?.string ?? "unknown", reason: item["reason"]?.string ?? "")
        }
        let presentation = CataloguePresentation.from(json["presentation"])
        let registryShots = (presentation?.screenshots ?? []).prefix(10).enumerated().compactMap { index, shot -> Preview? in
            guard let url = shot.source else { return nil }
            let w = shot.width ?? 0, h = shot.height ?? 0
            return Preview(id: shot.sha256 ?? "screenshot-\(index)", source: url, alt: shot.alt, aspect: w > 0 && h > 0 ? w / h : nil)
        }
        let marketPreviews = (market?["previews"]?.array ?? []).prefix(10).enumerated().compactMap { index, item -> Preview? in
            guard item["type"]?.string ?? "image" == "image", let url = Self.https(item["source"]?.string) else { return nil }
            let w = item["width"]?.number, h = item["height"]?.number
            return Preview(id: item["id"]?.string ?? "preview-\(index)", source: url, alt: item["alt"]?.string,
                           aspect: (w ?? 0) > 0 && (h ?? 0) > 0 ? w! / h! : nil)
        }
        // Registry presentation (latest published version) wins over legacy marketplace fields.
        previews = registryShots.isEmpty ? Array(marketPreviews) : Array(registryShots)
        platforms = (json["compatibility"]?["platforms"]?.array ?? []).compactMap(\.string)
        minimumHostVersion = json["compatibility"]?["minimumModulaHostVersion"]?.string
        iconURL = presentation?.icon?.source ?? Self.https(market?["icon"]?.string ?? market?["icon"]?["source"]?.string)
        coverURL = presentation?.cover?.source ?? Self.https(market?["cover"]?.string ?? market?["cover"]?["source"]?.string)
    }

    /// Only absolute https URLs are loaded remotely.
    static func https(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    var highRiskCount: Int { permissions.filter { ["high", "restricted"].contains($0.risk) }.count }
}

/// Where a piece of store artwork comes from. Artwork is only ever loaded from the
/// verified registry listing (https URLs); the app bundles no module art. When there is
/// no source the view draws a neutral placeholder.
enum ModuleArtSource: Equatable, Sendable {
    case remote(URL)

    init?(_ raw: String?) {
        guard let raw, !raw.isEmpty, let url = ModuleListing.https(raw) else { return nil }
        self = .remote(url)
    }
}

struct ModuleScreenshot: Equatable, Identifiable, Sendable {
    let id: String
    let source: ModuleArtSource
    let alt: String
    let aspect: Double
}

/// Store artwork resolved from the registry listing; anything missing is drawn as a
/// neutral placeholder by the views.
struct ModuleArtwork: Equatable, Sendable {
    var icon: ModuleArtSource?
    var cover: ModuleArtSource?
    var screenshots: [ModuleScreenshot]

    /// The detail listing wins; the catalogue list item's registry presentation (same
    /// latest published version) fills anything the listing has not loaded yet.
    init(listing: ModuleListing?, product: CatalogueProduct? = nil) {
        let presentation = product?.presentation
        icon = (listing?.iconURL ?? presentation?.icon?.source).map(ModuleArtSource.remote)
        cover = (listing?.coverURL ?? presentation?.cover?.source).map(ModuleArtSource.remote)
        let listed = (listing?.previews ?? []).map {
            ModuleScreenshot(id: $0.id, source: .remote($0.source), alt: $0.alt ?? "Screenshot", aspect: $0.aspect ?? 0.56)
        }
        let fallback = (presentation?.screenshots ?? []).enumerated().compactMap { index, shot -> ModuleScreenshot? in
            guard let url = shot.source else { return nil }
            let w = shot.width ?? 0, h = shot.height ?? 0
            return ModuleScreenshot(id: shot.sha256 ?? "screenshot-\(index)", source: .remote(url), alt: shot.alt ?? "Screenshot",
                                    aspect: w > 0 && h > 0 ? w / h : 0.56)
        }
        screenshots = listed.isEmpty ? fallback : listed
    }
}

struct ModulePermissionRecord: Identifiable, Hashable, Sendable {
    var id: String { capability }
    var capability: String
    var purpose: String
    var state: String
}

enum ModuleHostPermissions {
    static func records(from manifest: ModuleManifest?) -> [ModulePermissionRecord] {
        guard let manifest else { return [] }
        return manifest.permissions.map { permission in
            ModulePermissionRecord(
                capability: permission,
                purpose: purpose(for: permission),
                state: "Declared · enforced by HostBridge"
            )
        }
    }

    static func purpose(for permission: String) -> String {
        switch permission {
        case "backend.records.list", "backend.records.get", "storage:records":
            return "Read records this module stores on your account"
        case "backend.records.create", "backend.records.update", "backend.records.delete":
            return "Create or change records this module stores on your account"
        case "settings:register":
            return "Register settings screens. This does not allow reading or writing settings values."
        case "settings:read":
            return "Read this module’s settings"
        case "settings:write":
            return "Change this module’s settings"
        case "notifications":
            return "Notify you about module activity"
        case "mediaPicker":
            return "Open the system photo or file picker"
        case "share":
            return "Open the system share sheet"
        case "biometrics":
            return "Use Face ID or Touch ID for this module"
        case "secureStorage":
            return "Store secrets for this module in the Keychain"
        case "localIntelligence":
            return "Use on-device Nodus. Content marked localOnly never leaves this iPhone."
        case "backgroundTask":
            return "Run a short background task for this module"
        default:
            if permission.contains(":read") { return "Read \(permission)" }
            if permission.contains(":write") { return "Write \(permission)" }
            return "Requested capability: \(permission)"
        }
    }
}
