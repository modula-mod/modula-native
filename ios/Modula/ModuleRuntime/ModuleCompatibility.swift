import Foundation

/// Strict `MAJOR.MINOR.PATCH` version (no pre-release/build metadata: host and bridge
/// versions never carry them, and anything else fails closed).
struct SemanticVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    let major: Int, minor: Int, patch: Int

    init(_ major: Int, _ minor: Int, _ patch: Int) { self.major = major; self.minor = minor; self.patch = patch }

    init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            // Digits only, no leading zeros (semver §2), bounded length.
            guard !part.isEmpty, part.count <= 9, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  part == "0" || part.first != "0", let value = Int(part) else { return nil }
            numbers.append(value)
        }
        self.init(numbers[0], numbers[1], numbers[2])
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    var description: String { "\(major).\(minor).\(patch)" }
}

/// npm-style range subset, mirrored by `satisfies` in `@modula/module-contracts` and by
/// `packages/module-contracts/test-vectors/semver.json`:
/// - a bare version (`0.1.0`) means caret (`^0.1.0`): compatible within the same
///   major, or the same minor while major is 0 (0.x minors are breaking);
/// - `^`, `~`, `=`, `>`, `>=`, `<`, `<=`, `X.Y.x`, `*`;
/// - space-separated comparators are AND, `||` is OR.
/// Anything unparseable fails closed (never satisfied).
enum SemverRange {
    static func satisfies(_ version: String, range: String) -> Bool {
        guard let version = SemanticVersion(version) else { return false }
        return satisfies(version, range: range)
    }

    static func satisfies(_ version: SemanticVersion, range: String) -> Bool {
        let trimmed = range.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 128 else { return false }
        let alternatives = trimmed.components(separatedBy: "||")
        return alternatives.contains { alternative in
            let comparators = alternative.split(separator: " ").map(String.init)
            guard !comparators.isEmpty else { return false }
            var all = true
            for comparator in comparators {
                guard let ok = evaluate(comparator, version) else { return false }
                all = all && ok
            }
            return all
        }
    }

    /// nil when the comparator is malformed (the whole range then fails closed).
    private static func evaluate(_ comparator: String, _ v: SemanticVersion) -> Bool? {
        if comparator == "*" || comparator == "x" { return true }
        for op in [">=", "<=", ">", "<", "="] where comparator.hasPrefix(op) {
            guard let bound = SemanticVersion(String(comparator.dropFirst(op.count))) else { return nil }
            switch op {
            case ">=": return v >= bound
            case "<=": return v <= bound
            case ">": return v > bound
            case "<": return v < bound
            default: return v == bound
            }
        }
        if comparator.hasPrefix("~") {
            guard let bound = SemanticVersion(String(comparator.dropFirst())) else { return nil }
            return v >= bound && v < SemanticVersion(bound.major, bound.minor + 1, 0)
        }
        if comparator.hasSuffix(".x") {
            let parts = comparator.dropLast(2).split(separator: ".")
            guard parts.count == 2, let base = SemanticVersion("\(parts[0]).\(parts[1]).0") else { return nil }
            return v >= base && v < SemanticVersion(base.major, base.minor + 1, 0)
        }
        let caret = comparator.hasPrefix("^") ? String(comparator.dropFirst()) : comparator
        guard let bound = SemanticVersion(caret) else { return nil }
        return v >= bound && v < caretCeiling(bound)
    }

    private static func caretCeiling(_ v: SemanticVersion) -> SemanticVersion {
        if v.major > 0 { return SemanticVersion(v.major + 1, 0, 0) }
        if v.minor > 0 { return SemanticVersion(0, v.minor + 1, 0) }
        return SemanticVersion(0, 0, v.patch + 1)
    }
}

/// Why a manifest can or cannot run on this host. `minHostVersion`/`minBridgeVersion`
/// are semver ranges evaluated against what the host implements.
enum ModuleCompatibility: Equatable, Sendable {
    case compatible
    case unsupportedRuntime(String)
    /// The module needs a newer host/bridge than this app ships: the user must update Modula.
    case updateRequired(field: String, required: String, actual: String)
    /// The module targets an older, no-longer-compatible contract: the module must update.
    case moduleOutdated(field: String, required: String, actual: String)

    static let supportedRuntimes: Set<String> = ["react-native", "declarative", "product-ui", "web-game"]
    /// Bundled RN modules still declare `^0.1.0`; Product UI modules declare `>=1.0.0`.
    static let advertisedHostVersions = ["0.1.0", "1.0.0", "1.1.0"]

    static func evaluate(_ manifest: ModuleManifest, hostVersion: String, bridgeVersion: String) -> Self {
        evaluate(manifest, hostVersions: [hostVersion], bridgeVersion: bridgeVersion)
    }

    static func evaluate(_ manifest: ModuleManifest, hostVersions: [String], bridgeVersion: String) -> Self {
        guard Self.supportedRuntimes.contains(manifest.runtime) else { return .unsupportedRuntime(manifest.runtime) }
        if hostVersions.contains(where: { SemverRange.satisfies($0, range: manifest.minHostVersion) }) {
            guard SemverRange.satisfies(bridgeVersion, range: manifest.minBridgeVersion) else {
                if let host = SemanticVersion(bridgeVersion), let floor = lowestBound(manifest.minBridgeVersion), floor < host {
                    return .moduleOutdated(field: "minBridgeVersion", required: manifest.minBridgeVersion, actual: bridgeVersion)
                }
                return .updateRequired(field: "minBridgeVersion", required: manifest.minBridgeVersion, actual: bridgeVersion)
            }
            return .compatible
        }
        let actual = hostVersions.last ?? hostVersions.first ?? "0.0.0"
        if let host = SemanticVersion(actual), let floor = lowestBound(manifest.minHostVersion), floor < host {
            return .moduleOutdated(field: "minHostVersion", required: manifest.minHostVersion, actual: actual)
        }
        return .updateRequired(field: "minHostVersion", required: manifest.minHostVersion, actual: actual)
    }

    /// The smallest version a simple range admits, used only to explain a mismatch.
    private static func lowestBound(_ range: String) -> SemanticVersion? {
        let first = range.components(separatedBy: "||")[0].split(separator: " ").first.map(String.init) ?? ""
        let stripped = first.trimmingCharacters(in: CharacterSet(charactersIn: "^~>=<"))
        if stripped.hasSuffix(".x") { return SemanticVersion(stripped.dropLast(2) + ".0") }
        return SemanticVersion(stripped)
    }
}
