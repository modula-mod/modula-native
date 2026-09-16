import Foundation

enum ModulePrimaryAction: Equatable, Sendable {
    case install
    case installing
    case open
    case update
    case updating
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
        case .unavailable: "Unavailable"
        case .incompatible: "Incompatible"
        case .comingSoon: "Coming Soon"
        }
    }

    var isEnabled: Bool {
        switch self {
        case .open, .install, .update: true
        default: false
        }
    }
}

extension CatalogueProduct {
    /// Catalogue does not currently emit coverImage in native DTOs. Brand fallback is used instead.
    var coverImageURL: URL? { nil }
}

enum ModuleInstallMutationCapability {
    /// Exact install HTTP is documented historically but unverified this run.
    static let liveInstall = false
    static let liveUpdate = false
}

struct ModuleDetailPresentation: Equatable {
    var product: CatalogueProduct
    var installed: Bool
    var bundled: Bool
    var coverURL: URL?

    var primaryAction: ModulePrimaryAction {
        let status = product.installability?.status.lowercased() ?? product.status.lowercased()
        if status.contains("incompatible") { return .incompatible }
        if status.contains("coming") || (!product.installable && !installed && !bundled) { return .comingSoon }
        if installed || bundled { return .open }
        if product.installable { return ModuleInstallMutationCapability.liveInstall ? .install : .install }
        return .unavailable
    }

    var tags: [String] {
        var values: [String] = []
        if !product.productKind.isEmpty { values.append(product.productKind.capitalized) }
        values.append(contentsOf: product.platforms.map { $0.uppercased() == "IOS" ? "iOS" : $0.capitalized })
        if product.installable { values.append("Installable") }
        return values
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
        case "backend.records.list", "backend.records.get", "backend.records.create", "backend.records.update", "backend.records.delete":
            "Local records stored for this module"
        case "notifications":
            "Notify you about module activity"
        default:
            "Required by the module runtime contract"
        }
    }
}
