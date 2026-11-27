import CryptoKit
import Foundation

/// How a registry version relates to the account's installation.
enum ModuleVersionDirection: String, Equatable, Sendable {
    case upgrade, downgrade, current, install

    init(server: String?, current: Bool) {
        if current { self = .current; return }
        switch server {
        case "upgrade": self = .upgrade
        case "downgrade": self = .downgrade
        case "none": self = .current
        default: self = .install
        }
    }
}

/// One row of `GET /v1/modules/:id/versions`: an immutable registry release annotated
/// relative to the installation and gated by the registry (trust + compatibility).
struct ModuleVersionOption: Equatable, Identifiable, Sendable {
    struct Blocker: Equatable, Sendable { let code: String; let message: String }

    var id: String { version }
    let version: String
    let releaseId: String
    let releaseState: String
    let publishedAt: Date?
    let releaseNotes: String?
    let signatureState: String
    let verified: Bool
    let revoked: Bool
    let quarantined: Bool
    let trustWarnings: [String]
    let direction: ModuleVersionDirection
    let isCurrent: Bool
    let isLatest: Bool
    let switchable: Bool
    let blockers: [Blocker]

    init?(json: JSONValue) {
        guard let version = json["version"]?.string, let releaseId = json["releaseId"]?.string else { return nil }
        self.version = version
        self.releaseId = releaseId
        releaseState = json["releaseState"]?.string ?? "unknown"
        publishedAt = ModuleListing.date(json["publishedAt"]?.string)
        releaseNotes = json["releaseNotes"]?.string.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let trust = json["trust"]
        signatureState = trust?["signatureState"]?.string ?? "unsigned"
        verified = trust?["verified"]?.bool ?? false
        revoked = trust?["revoked"]?.bool ?? false
        quarantined = trust?["quarantined"]?.bool ?? false
        trustWarnings = (trust?["warnings"]?.array ?? []).compactMap(\.string)
        isCurrent = json["current"]?.bool ?? false
        isLatest = json["latest"]?.bool ?? false
        direction = ModuleVersionDirection(server: json["direction"]?.string, current: isCurrent)
        switchable = json["switchable"]?.bool ?? false
        blockers = (json["blockers"]?.array ?? []).compactMap { item in
            guard let code = item["code"]?.string else { return nil }
            return Blocker(code: code, message: item["message"]?.string ?? code)
        }
    }

    /// The registry refused this release for this app's host version.
    var requiresNewerHost: Bool { blockers.contains { $0.code == "HOST_INCOMPATIBLE" } }

    /// Plain-language signature/trust state for the row.
    var trustLabel: String {
        if revoked { return "Revoked" }
        if quarantined { return "Quarantined" }
        switch signatureState {
        case "valid": return verified ? "Signed · Verified" : "Signed"
        case "unsigned": return verified ? "Registry verified · Unsigned" : "Unsigned"
        case "invalid": return "Invalid signature"
        case "unknownKey": return "Unknown signing key"
        case "revokedKey": return "Revoked signing key"
        default: return signatureState.capitalized
        }
    }

    var trustSymbol: String {
        if revoked || quarantined || ["invalid", "unknownKey", "revokedKey"].contains(signatureState) { return "xmark.shield.fill" }
        return signatureState == "valid" ? "checkmark.seal.fill" : "checkmark.shield"
    }
}

struct ModuleVersionList: Equatable, Sendable {
    let moduleId: String
    let installedVersion: String?
    let latestVersion: String?
    let updateAvailable: Bool
    let versions: [ModuleVersionOption]

    init?(json: JSONValue) {
        guard let moduleId = json["moduleId"]?.string else { return nil }
        self.moduleId = moduleId
        installedVersion = json["installedVersion"]?.string
        latestVersion = json["latestVersion"]?.string
        updateAvailable = json["updateAvailable"]?.bool ?? false
        versions = (json["versions"]?.array ?? []).prefix(100).compactMap(ModuleVersionOption.init(json:))
    }
}

/// What a row offers. "Update" is reserved for the newest release when it is ahead of the
/// installation; any other switchable release is "Install this version", labelled as an
/// upgrade or a downgrade.
enum ModuleVersionAction: Equatable, Sendable {
    case installed
    case update
    case installThisVersion(ModuleVersionDirection)
    case needsNewerApp
    case unavailable(String)

    /// Compatibility is the registry's call: it evaluates the release against
    /// `ModulaHost.version`. "Needs a newer app" appears only when the registry says the
    /// release requires a newer host (`HOST_INCOMPATIBLE`), never from comparing module
    /// version numbers on the device.
    static func resolve(_ option: ModuleVersionOption, installed: Bool, busy: Bool) -> ModuleVersionAction {
        if option.isCurrent { return .installed }
        guard installed else { return .unavailable("Install the module first") }
        if option.requiresNewerHost { return .needsNewerApp }
        if !option.switchable { return .unavailable(option.blockers.first?.message ?? "Not available") }
        if busy { return .unavailable("Another change is in progress") }
        if option.direction == .upgrade && option.isLatest { return .update }
        return .installThisVersion(option.direction)
    }

    var title: String {
        switch self {
        case .installed: "Installed"
        case .update: "Update"
        case .installThisVersion: "Install this version"
        case .needsNewerApp: "Needs app update"
        case .unavailable: "Unavailable"
        }
    }

    var badge: String? {
        switch self {
        case .installThisVersion(.upgrade): "Upgrade"
        case .installThisVersion(.downgrade): "Downgrade"
        default: nil
        }
    }

    var isEnabled: Bool {
        switch self {
        case .update, .installThisVersion: true
        default: false
        }
    }
}

/// `POST /v1/modules/:id/version-preview`: the confirmation facts for a switch.
struct ModuleVersionPreview: Equatable, Sendable {
    struct Permission: Equatable, Identifiable, Sendable {
        var id: String { permission }
        let permission: String
        let risk: String
        let reason: String?
    }
    struct Warning: Equatable, Identifiable, Sendable {
        var id: String { code }
        let code: String
        let message: String
    }

    let moduleId: String
    let fromVersion: String
    let toVersion: String
    let direction: ModuleVersionDirection
    let allowed: Bool
    let blockers: [ModuleVersionOption.Blocker]
    let addedPermissions: [Permission]
    let removedPermissions: [String]
    let requiresConsent: [String]
    let highRiskIncrease: Bool
    let dataSchemaOlder: Bool
    let missingCollections: [String]
    let warnings: [Warning]
    let descriptor: ModuleInstallDescriptor

    init?(json: JSONValue) {
        guard let moduleId = json["moduleId"]?.string, let from = json["fromVersion"]?.string, let to = json["toVersion"]?.string,
              let descriptorJSON = json["descriptor"], let descriptor = ModuleInstallDescriptor(json: descriptorJSON) else { return nil }
        self.moduleId = moduleId
        fromVersion = from
        toVersion = to
        let noop = json["noop"]?.bool ?? false
        direction = ModuleVersionDirection(server: json["direction"]?.string, current: noop)
        allowed = json["allowed"]?.bool ?? false
        blockers = (json["blockers"]?.array ?? []).compactMap { item in
            item["code"]?.string.map { ModuleVersionOption.Blocker(code: $0, message: item["message"]?.string ?? $0) }
        }
        let permissions = json["permissions"]
        addedPermissions = (permissions?["added"]?.array ?? []).prefix(100).compactMap { item in
            item["permission"]?.string.map { Permission(permission: $0, risk: item["risk"]?.string ?? "unknown", reason: item["reason"]?.string) }
        }
        removedPermissions = (permissions?["removed"]?.array ?? []).prefix(100).compactMap(\.string)
        requiresConsent = (permissions?["requiresConsent"]?.array ?? []).prefix(100).compactMap(\.string)
        highRiskIncrease = permissions?["highRiskIncrease"]?.bool ?? false
        dataSchemaOlder = json["dataSchema"]?["older"]?.bool ?? false
        missingCollections = (json["dataSchema"]?["missingInTarget"]?.array ?? []).compactMap(\.string)
        warnings = (json["warnings"]?.array ?? []).compactMap { item in
            item["code"]?.string.map { Warning(code: $0, message: item["message"]?.string ?? $0) }
        }
        self.descriptor = descriptor
    }

    var isDowngrade: Bool { direction == .downgrade }

    /// The downgrade warning the confirmation sheet must show, if any.
    var downgradeWarning: String? {
        guard isDowngrade else { return nil }
        if let schema = warnings.first(where: { $0.code == "DATA_SCHEMA_OLDER" }) { return schema.message }
        return "You are moving back to an older version. Your data stays on your account."
    }
}

/// The registry's immutable install descriptor (`descriptorVersion` 1.0.0). The raw JSON is
/// kept so its digest can be recomputed exactly as the registry computed it.
struct ModuleInstallDescriptor: Equatable, Sendable {
    let raw: JSONValue
    let moduleId: String
    let version: String
    let registryReleaseId: String
    let descriptorSha256: String
    let artifactSha256: String?
    let artifactRef: String?
    let adapterManifestSha256: String?
    let productManifestSha256: String?
    let frontendSha256: String?
    let frontendRef: String?
    let signatureState: String
    let revoked: Bool
    let quarantined: Bool
    let grantedPermissions: [String]

    init?(json: JSONValue) {
        guard json["descriptorVersion"]?.string == "1.0.0",
              let moduleId = json["moduleId"]?.string, let version = json["version"]?.string,
              let releaseId = json["registryReleaseId"]?.string, let digest = json["descriptorSha256"]?.string else { return nil }
        raw = json
        self.moduleId = moduleId
        self.version = version
        registryReleaseId = releaseId
        descriptorSha256 = digest
        artifactSha256 = json["artifact"]?["sha256"]?.string
        artifactRef = json["artifact"]?["ref"]?.string
        adapterManifestSha256 = json["manifest"]?["adapterManifestSha256"]?.string
        productManifestSha256 = json["manifest"]?["productManifestSha256"]?.string
        frontendSha256 = json["frontend"]?["sha256"]?.string
        frontendRef = json["frontend"]?["ref"]?.string
        signatureState = json["trust"]?["signatureState"]?.string ?? "unsigned"
        revoked = json["trust"]?["revoked"]?.bool ?? true
        quarantined = json["trust"]?["quarantined"]?.bool ?? true
        grantedPermissions = (json["permissions"]?["granted"]?.array ?? []).compactMap(\.string)
    }

    /// SHA-256 over the canonical JSON of the descriptor body (digest and issuedAt removed),
    /// matching the registry's `descriptorDigest`.
    var computedSha256: String? {
        guard case .object(var body) = raw else { return nil }
        body.removeValue(forKey: "descriptorSha256")
        body.removeValue(forKey: "issuedAt")
        return CanonicalJSON.sha256Hex(.object(body))
    }
}

/// Digests the public registry publishes for one release
/// (`GET /v1/registry/modules/:id/versions/:version` → `registryTrust.digests`).
struct ModuleRegistryReleaseFacts: Equatable, Sendable {
    let registryReleaseId: String
    let releaseSha256: String?
    let adapterManifestSha256: String?
    let productManifestSha256: String?
    let frontendSha256: String?

    init?(json: JSONValue) {
        guard let releaseId = json["registryReleaseId"]?.string ?? json["releaseId"]?.string else { return nil }
        registryReleaseId = releaseId
        let digests = json["registryTrust"]?["digests"]
        releaseSha256 = digests?["releaseSha256"]?.string ?? json["releaseSha256"]?.string
        adapterManifestSha256 = digests?["adapterManifestSha256"]?.string ?? json["manifestSha256"]?.string
        productManifestSha256 = digests?["productManifestSha256"]?.string
        frontendSha256 = digests?["frontendSha256"]?.string
    }

    init(registryReleaseId: String, releaseSha256: String?, adapterManifestSha256: String?, productManifestSha256: String?, frontendSha256: String?) {
        self.registryReleaseId = registryReleaseId
        self.releaseSha256 = releaseSha256
        self.adapterManifestSha256 = adapterManifestSha256
        self.productManifestSha256 = productManifestSha256
        self.frontendSha256 = frontendSha256
    }
}

enum InstallDescriptorVerificationError: Error, Equatable, LocalizedError {
    case digestMismatch
    case wrongRelease
    case digestMalformed(String)
    case registryMismatch(String)
    case untrustedRef(String)
    case releaseNotTrusted(String)

    var errorDescription: String? {
        switch self {
        case .digestMismatch: "The install descriptor failed its integrity check."
        case .wrongRelease: "The install descriptor is for a different release."
        case .digestMalformed(let field): "The install descriptor has a malformed \(field) digest."
        case .registryMismatch(let field): "The install descriptor’s \(field) digest doesn’t match the registry."
        case .untrustedRef(let field): "The install descriptor points \(field) outside the Modula registry."
        case .releaseNotTrusted(let reason): "This release can’t be installed: \(reason)."
        }
    }
}

/// Client-side check of an install descriptor before acting on it. The registry is the
/// trust authority: every digest must match what the public registry publishes for the
/// release, the descriptor's own digest must recompute, and artifact/frontend refs may
/// only point at the registry origin (never GitHub or any other host).
enum InstallDescriptorVerifier {
    private static let rejectedSignatures: Set<String> = ["invalid", "unknownKey", "revokedKey"]

    static func verify(_ descriptor: ModuleInstallDescriptor, moduleId: String, version: String,
                       registry: ModuleRegistryReleaseFacts, registryHost: String?) throws {
        guard descriptor.computedSha256 == descriptor.descriptorSha256 else { throw InstallDescriptorVerificationError.digestMismatch }
        guard descriptor.moduleId == moduleId, descriptor.version == version,
              descriptor.registryReleaseId == registry.registryReleaseId else { throw InstallDescriptorVerificationError.wrongRelease }
        let pairs: [(String, String?, String?)] = [
            ("artifact", descriptor.artifactSha256, registry.releaseSha256),
            ("manifest", descriptor.adapterManifestSha256, registry.adapterManifestSha256),
            ("product manifest", descriptor.productManifestSha256, registry.productManifestSha256),
            ("frontend", descriptor.frontendSha256, registry.frontendSha256),
        ]
        for (field, value, expected) in pairs {
            if let value, !isHex64(value) { throw InstallDescriptorVerificationError.digestMalformed(field) }
            if value != expected { throw InstallDescriptorVerificationError.registryMismatch(field) }
        }
        guard descriptor.adapterManifestSha256 != nil else { throw InstallDescriptorVerificationError.digestMalformed("manifest") }
        for (field, ref) in [("the artifact", descriptor.artifactRef), ("the frontend", descriptor.frontendRef)] {
            guard let ref else { continue }
            // Registry-relative refs resolve against the registry origin itself.
            if ref.hasPrefix("/"), !ref.hasPrefix("//") { continue }
            guard let url = URL(string: ref), url.scheme == "https", let host = url.host, url.user == nil,
                  let registryHost, host.caseInsensitiveCompare(registryHost) == .orderedSame else {
                throw InstallDescriptorVerificationError.untrustedRef(field)
            }
        }
        if descriptor.revoked { throw InstallDescriptorVerificationError.releaseNotTrusted("it was revoked") }
        if descriptor.quarantined { throw InstallDescriptorVerificationError.releaseNotTrusted("it is quarantined") }
        if rejectedSignatures.contains(descriptor.signatureState) {
            throw InstallDescriptorVerificationError.releaseNotTrusted("its signature is \(descriptor.signatureState)")
        }
    }

    static func isHex64(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// GreenField serializes Ed25519 signatures with Node's unpadded `base64url`
    /// encoding. Accept padded RFC 4648 base64 as a compatibility input, but
    /// always require the exact 64-byte Ed25519 signature length.
    static func isEd25519Signature(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 88,
              value.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
                    || [43, 45, 47, 61, 95].contains(byte)
              }) else { return false }
        var normalized = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.utf8.count % 4
        guard remainder != 1 else { return false }
        if remainder > 0 { normalized += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: normalized)?.count == 64
    }
}

/// Exact GreenField closure approved for an optional install. The lock digest is
/// recomputed locally and every dependency is pinned before any bytes download.
struct PackageInstallPlan: Sendable {
    struct Package: Sendable {
        let id: String
        let version: String
        let releaseID: String
        let category: String
        let sha256: String
        let compressedBytes: Int64
        let installedBytes: Int64
        let mediaType: String
        let downloadRef: String
        let sharing: String
        let signatureKeyID: String
        let statementDigest: String
        let dependencies: [String]
        let requiredCapabilities: [String]
    }

    let lockSha256: String
    let packages: [Package]
    let requested: String
    let aggregateCompressedBytes: Int64
    let aggregateInstalledBytes: Int64
    let newDownloadBytes: Int64
    let reusedDigests: [String]

    init?(json: JSONValue, requested: String) {
        guard let lock = json["lock"], lock["schemaVersion"]?.string == "modula.package-lock.1",
              let digest = json["lockSha256"]?.string, InstallDescriptorVerifier.isHex64(digest),
              CanonicalJSON.sha256Hex(lock) == digest,
              lock["requested"]?.array?.compactMap(\.string).contains(requested) == true,
              let rows = lock["packages"]?.array, !rows.isEmpty, rows.count <= 128 else { return nil }
        var packages: [Package] = []
        var seen = Set<String>()
        for row in rows {
            guard row["schemaVersion"]?.string == PackageMediaCompatibility.packageSchemaVersion,
                  let id = row["packageId"]?.string, seen.insert(id).inserted,
                  let version = row["version"]?.string, let releaseID = row["releaseId"]?.string,
                  let category = row["category"]?.string,
                  ["module", "web-runtime", "game-content", "model-data", "asset-pack"].contains(category),
                  let sha256 = row["artifact"]?["sha256"]?.string, InstallDescriptorVerifier.isHex64(sha256),
                  let compressed = row["artifact"]?["compressedSizeBytes"]?.number,
                  let installed = row["artifact"]?["installedSizeEstimateBytes"]?.number,
                  compressed > 0, compressed <= 1_073_741_824, installed > 0, installed <= 4_294_967_296,
                  let mediaType = row["artifact"]?["mediaType"]?.string, !mediaType.isEmpty,
                  let ref = row["artifact"]?["download"]?["pathOrUrl"]?.string,
                  let authorization = row["artifact"]?["download"]?["authorization"]?.string,
                  row["artifact"]?["download"]?["range"]?.bool == true,
                  let sharing = row["sharing"]?.string,
                  ["public-immutable", "account-private"].contains(sharing),
                  (sharing == "public-immutable" && authorization == "none") ||
                    (sharing == "account-private" && authorization == "bearer"),
                  row["trust"]?["verified"]?.bool == true,
                  row["trust"]?["publisherVerified"]?.bool == true,
                  row["trust"]?["revoked"]?.bool == false,
                  row["signature"]?["algorithm"]?.string == "Ed25519",
                  let keyID = row["signature"]?["keyId"]?.string, !keyID.isEmpty,
                  let signature = row["signature"]?["signature"]?.string,
                  InstallDescriptorVerifier.isEd25519Signature(signature),
                  let statementDigest = row["signature"]?["statementDigest"]?.string,
                  InstallDescriptorVerifier.isHex64(statementDigest),
                  let minimumHostVersion = row["minimumHostVersion"]?.string, !minimumHostVersion.isEmpty,
                  row["platforms"]?.array?.compactMap(\.string).contains("ios") == true,
                  let deps = row["dependencies"]?.array?.compactMap({ $0["packageId"]?.string }),
                  let required = row["requiredCapabilities"]?.array?.compactMap(\.string),
                  required.count <= 256, required.allSatisfy({ !$0.isEmpty }) else { return nil }
            packages.append(Package(id: id, version: version, releaseID: releaseID, category: category,
                                    sha256: sha256, compressedBytes: Int64(compressed), installedBytes: Int64(installed),
                                    mediaType: mediaType, downloadRef: ref, sharing: sharing,
                                    signatureKeyID: keyID, statementDigest: statementDigest,
                                    dependencies: deps, requiredCapabilities: required))
        }
        let ids = Set(packages.map(\.id))
        guard ids.contains(requested), packages.allSatisfy({ Set($0.dependencies).isSubset(of: ids) }),
              let totalCompressed = lock["aggregateCompressedBytes"]?.number,
              let totalInstalled = lock["aggregateInstalledEstimateBytes"]?.number,
              let newDownload = lock["newDownloadBytes"]?.number,
              let reused = lock["reusedArtifactDigests"]?.array?.compactMap(\.string),
              reused.allSatisfy(InstallDescriptorVerifier.isHex64),
              totalCompressed >= 0, totalInstalled >= 0, newDownload >= 0 else { return nil }
        self.lockSha256 = digest
        self.packages = packages
        self.requested = requested
        aggregateCompressedBytes = Int64(totalCompressed)
        aggregateInstalledBytes = Int64(totalInstalled)
        newDownloadBytes = Int64(newDownload)
        reusedDigests = reused
    }

    func package(_ id: String) -> Package? { packages.first { $0.id == id } }
}

/// Verifies that a cached rollback target still resolves to the same trusted,
/// unrevoked game and runtime artifacts. GreenField supplies the exact closure;
/// the host never selects a replacement runtime during recovery.
enum RollbackPackageClosure {
    static func isEligible(_ response: JSONValue, for release: ModuleCachedRelease) -> Bool {
        guard let gameDigest = release.gameSha256, let runtimeDigest = release.runtimeSha256,
              let lock = response["lock"], lock["schemaVersion"]?.string == "modula.package-lock.1",
              let lockDigest = response["lockSha256"]?.string,
              InstallDescriptorVerifier.isHex64(lockDigest), CanonicalJSON.sha256Hex(lock) == lockDigest,
              lock["requested"]?.array?.compactMap(\.string).contains(release.moduleId) == true,
              let rows = lock["packages"]?.array, !rows.isEmpty, rows.count <= 128 else { return false }
        var packages: [String: JSONValue] = [:]
        for row in rows {
            guard let id = row["packageId"]?.string, packages[id] == nil,
                  let digest = row["artifact"]?["sha256"]?.string,
                  InstallDescriptorVerifier.isHex64(digest),
                  row["trust"]?["verified"]?.bool == true,
                  row["trust"]?["publisherVerified"]?.bool == true,
                  row["trust"]?["revoked"]?.bool == false,
                  row["signature"]?["algorithm"]?.string == "Ed25519",
                  row["dependencies"]?.array?.allSatisfy({ $0["packageId"]?.string != nil }) == true else { return false }
            packages[id] = row
        }
        let ids = Set(packages.keys)
        guard packages.count == 2, packages.values.allSatisfy({ row in
            Set(row["dependencies"]?.array?.compactMap({ $0["packageId"]?.string }) ?? []).isSubset(of: ids)
        }), let game = packages[release.moduleId],
              game["category"]?.string == "game-content",
              game["version"]?.string == release.version,
              game["releaseId"]?.string == release.releaseId,
              game["artifact"]?["sha256"]?.string == gameDigest,
              game["dependencies"]?.array?.count == 1,
              let runtimeID = game["dependencies"]?.array?.first(where: {
                  packages[$0["packageId"]?.string ?? ""]?["category"]?.string == "web-runtime"
              })?["packageId"]?.string,
              let runtime = packages[runtimeID], runtime["category"]?.string == "web-runtime",
              runtime["artifact"]?["sha256"]?.string == runtimeDigest else { return false }
        return true
    }
}

/// Canonical JSON identical to Greenfield's `canonicalJsonStringify`: object keys sorted by
/// UTF-16 code units, no whitespace, `JSON.stringify` string escaping and number formatting.
enum CanonicalJSON {
    static func string(_ value: JSONValue) -> String {
        var out = ""
        write(value, into: &out)
        return out
    }

    static func sha256Hex(_ value: JSONValue) -> String {
        SHA256.hash(data: Data(string(value).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func write(_ value: JSONValue, into out: inout String) {
        switch value {
        case .null: out += "null"
        case .bool(let flag): out += flag ? "true" : "false"
        case .number(let number): out += format(number)
        case .string(let text): quote(text, into: &out)
        case .array(let items):
            out += "["
            for (index, item) in items.enumerated() {
                if index > 0 { out += "," }
                write(item, into: &out)
            }
            out += "]"
        case .object(let fields):
            out += "{"
            let keys = fields.keys.sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }
            for (index, key) in keys.enumerated() {
                if index > 0 { out += "," }
                quote(key, into: &out)
                out += ":"
                write(fields[key]!, into: &out)
            }
            out += "}"
        }
    }

    private static func format(_ number: Double) -> String {
        guard number.isFinite else { return "null" }
        if number == number.rounded(), abs(number) < 1e21 { return String(Int64(number)) }
        return String(number)
    }

    private static func quote(_ text: String, into out: inout String) {
        out += "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 { out += String(format: "\\u%04x", scalar.value) } else { out.unicodeScalars.append(scalar) }
            }
        }
        out += "\""
    }
}
