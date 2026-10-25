import CryptoKit
import Foundation
import Observation
import os
import SwiftUI

private let packageLog = Logger(subsystem: "digital.modula.native", category: "MolibooPackages")

// MARK: - MOL-03E Moliboo character packages
//
// Character packages are signed, immutable, versioned GreenField `asset-pack` releases (descriptor schema
// `modula.package.1`, the same shape as the GreenField package-distribution contract). They carry trusted declarative
// data only — a character patch (palette, proportions, silhouette part tweaks, fit values) and optional PNG media —
// which the one native 2D renderer draws. Nothing downloaded is ever executed and no native code moves into packages.
//
// Pipeline: catalogue → descriptor → download (bounded) → SHA-256 → Ed25519 signature (ModuleReleaseTrust, the same
// verifier as signed modules) → container validation (paths, sizes, per-file digests) → patch validation against the
// canonical registry → staging directory → atomic activation (rename + atomic index write) → health check → rollback to
// the previous good version on failure. Installed packages live under Application Support/Modula/Packages/moliboo and
// work offline; nothing is downloaded at app launch.

enum MolibooPackageLimits {
    static let maxArtifactBytes = 6 * 1024 * 1024
    static let maxDecodedBytes = 8 * 1024 * 1024
    static let maxFiles = 16
    static let maxFileBytes = 4 * 1024 * 1024
    static let allowedExtensions: Set<String> = ["json", "png"]
    static let runtimeVersion = 1
}

// MARK: Wire formats

struct MolibooPackageDescriptor: Codable, Equatable, Sendable, Identifiable {
    struct Artifact: Codable, Equatable, Sendable {
        struct Download: Codable, Equatable, Sendable { var pathOrUrl: String; var authorization: String; var range: Bool }
        var sha256: String
        var compressedSizeBytes: Int
        var installedSizeEstimateBytes: Int
        var mediaType: String
        var download: Download
    }
    struct Signature: Codable, Equatable, Sendable { var algorithm: String; var keyId: String; var signature: String; var statementDigest: String? }
    struct Dependency: Codable, Equatable, Sendable { var packageId: String; var versionRange: String }
    struct Moliboo: Codable, Equatable, Sendable {
        var characterId: String
        var familyId: String
        var runtimeVersion: Int
        var assetCapabilities: [String]
        var rollbackCompatible: Bool
    }

    var schemaVersion: String
    var packageId: String
    var publisherId: String
    var category: String
    var version: String
    var releaseId: String
    var artifact: Artifact
    var signature: Signature
    var minimumHostVersion: String
    var platforms: [String]
    var dependencies: [Dependency]
    var requiredCapabilities: [String]
    var cachePolicy: String
    var sharing: String
    var moliboo: Moliboo

    var id: String { "\(packageId)@\(version)" }
}

struct MolibooPackageCatalog: Codable, Equatable, Sendable {
    static let schemaVersion = "modula.moliboo.catalog.1"
    var schemaVersion: String
    var packages: [MolibooPackageDescriptor]
}

/// The artifact: one JSON container with an explicit file inventory (no archive extraction).
struct MolibooAssetPackContainer: Codable, Equatable, Sendable {
    static let schemaVersion = "modula.moliboo.assetpack.1"
    static let mediaType = "application/vnd.modula.moliboo-asset-pack+json"
    struct File: Codable, Equatable, Sendable { var path: String; var mediaType: String; var sha256: String; var bytes: Int; var data: String }
    var schemaVersion: String
    var packageId: String
    var version: String
    var characterId: String
    var files: [File]
}

/// `character.json`: declarative artwork data for one Moliboo, drawn by the native renderer.
struct MolibooCharacterPatch: Codable, Equatable, Sendable {
    static let schemaVersion = "modula.moliboo.character.1"
    struct PaletteHex: Codable, Equatable, Sendable { var mid: String; var accent: String; var iris: String?; var light: String?; var dark: String?; var outline: String? }
    struct Size: Codable, Equatable, Sendable { var width: Double; var height: Double }
    struct Fit: Codable, Equatable, Sendable { var hatScale: Double?; var hatMaxWidth: Double?; var headTopExtra: Double? }
    var schemaVersion: String
    var characterId: String
    var key: String
    var assetVersion: String
    var palette: PaletteHex?
    var size: Size?
    var glow: String?
    var sparkles: Int?
    var removeParts: [String]?
    var form: String?
    var fit: Fit?
}

enum MolibooPackageError: Error, Equatable, LocalizedError {
    case unsupportedSchema(String)
    case wrongCategory
    case tooLarge
    case digestMismatch
    case signature(ModuleTrustError)
    case unsafePath(String)
    case corrupt(String)
    case incompatibleHost(String)
    case unknownCharacter(String)
    case dependency(String)
    case dependencyCycle(String)
    case invalidPatch(String)
    case notInstalled
    case nothingToRollBack
    case network(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let s): "Unsupported package schema \(s)."
        case .wrongCategory: "This package is not a Moliboo asset pack."
        case .tooLarge: "The package is larger than allowed."
        case .digestMismatch: "The package contents do not match their published digest."
        case .signature(let e): e.errorDescription ?? "The package signature is not trusted."
        case .unsafePath(let p): "The package contains an unsafe file path (\(p))."
        case .corrupt(let s): "The package is damaged (\(s))."
        case .incompatibleHost(let v): "This package needs Modula \(v) or newer."
        case .unknownCharacter(let c): "The package is for an unknown Moliboo (\(c))."
        case .dependency(let d): "A required package is missing (\(d))."
        case .dependencyCycle(let d): "The package dependencies form a cycle (\(d))."
        case .invalidPatch(let s): "The character data is invalid (\(s))."
        case .notInstalled: "This package is not installed."
        case .nothingToRollBack: "There is no previous version to restore."
        case .network(let s): "Download failed (\(s))."
        }
    }
}

// MARK: Validation (pure, unit-tested)

enum MolibooPackageValidator {
    static func sha256Hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func compareSemVer(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    /// Relative, normalised, no traversal, no hidden files, allowed extensions only.
    static func isSafe(path: String) -> Bool {
        guard !path.isEmpty, path.count <= 128, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0") else { return false }
        let comps = path.split(separator: "/", omittingEmptySubsequences: false)
        guard comps.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") }) else { return false }
        guard path.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.alphanumerics.contains($0) || "-_./".unicodeScalars.contains($0) }) else { return false }
        return MolibooPackageLimits.allowedExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    static func validate(descriptor d: MolibooPackageDescriptor, registry: MolibooCharacterRegistry?, hostVersion: String) throws {
        guard d.schemaVersion == "modula.package.1" else { throw MolibooPackageError.unsupportedSchema(d.schemaVersion) }
        guard d.category == "asset-pack", d.artifact.mediaType == MolibooAssetPackContainer.mediaType else { throw MolibooPackageError.wrongCategory }
        guard MolibooRegistryValidator.isSemVer(d.version) else { throw MolibooPackageError.corrupt("version") }
        guard d.artifact.sha256.count == 64, d.artifact.sha256.allSatisfy(\.isHexDigit) else { throw MolibooPackageError.corrupt("digest") }
        guard d.artifact.compressedSizeBytes > 0, d.artifact.compressedSizeBytes <= MolibooPackageLimits.maxArtifactBytes,
              d.artifact.installedSizeEstimateBytes <= MolibooPackageLimits.maxDecodedBytes else { throw MolibooPackageError.tooLarge }
        guard d.moliboo.runtimeVersion <= MolibooPackageLimits.runtimeVersion else { throw MolibooPackageError.unsupportedSchema("runtime \(d.moliboo.runtimeVersion)") }
        guard compareSemVer(hostVersion, d.minimumHostVersion) >= 0 else { throw MolibooPackageError.incompatibleHost(d.minimumHostVersion) }
        if let registry {
            guard let c = registry.character(id: d.moliboo.characterId), c.packageId == d.packageId, c.familyId == d.moliboo.familyId else {
                throw MolibooPackageError.unknownCharacter(d.moliboo.characterId)
            }
        }
    }

    /// Resolves the install order for `root` over the catalogue, rejecting missing dependencies and cycles.
    static func installOrder(for root: MolibooPackageDescriptor, catalog: [MolibooPackageDescriptor], installed: Set<String>) throws -> [MolibooPackageDescriptor] {
        let byID = Dictionary(catalog.map { ($0.packageId, $0) }, uniquingKeysWith: { a, b in compareSemVer(a.version, b.version) >= 0 ? a : b })
        var order: [MolibooPackageDescriptor] = [], visiting = Set<String>(), done = Set<String>()
        func visit(_ d: MolibooPackageDescriptor) throws {
            if done.contains(d.packageId) { return }
            if !visiting.insert(d.packageId).inserted { throw MolibooPackageError.dependencyCycle(d.packageId) }
            for dep in d.dependencies {
                if installed.contains(dep.packageId) { continue }
                guard let next = byID[dep.packageId] else { throw MolibooPackageError.dependency(dep.packageId) }
                try visit(next)
            }
            visiting.remove(d.packageId); done.insert(d.packageId); order.append(d)
        }
        try visit(root)
        return order
    }

    /// Verifies digest + signature over the raw artifact bytes, then the container inventory.
    static func verify(artifact data: Data, descriptor d: MolibooPackageDescriptor, policy: ModuleTrustPolicy) throws -> MolibooAssetPackContainer {
        guard data.count <= MolibooPackageLimits.maxArtifactBytes else { throw MolibooPackageError.tooLarge }
        guard sha256Hex(data) == d.artifact.sha256 else { throw MolibooPackageError.digestMismatch }
        guard d.signature.algorithm.lowercased() == "ed25519" else { throw MolibooPackageError.signature(.unsupportedAlgorithm) }
        guard let facts = ModuleSignedFacts(data: try JSONSerialization.data(withJSONObject: [
            "algorithm": "ed25519", "signature": d.signature.signature, "keyId": d.signature.keyId,
            "digest": d.artifact.sha256, "digestAlgorithm": "sha256",
        ])) else { throw MolibooPackageError.signature(.unsigned) }
        do { try ModuleReleaseTrust.verify(facts: facts, packagedDigest: nil, artifact: data, policy: policy) }
        catch let e as ModuleTrustError { throw MolibooPackageError.signature(e) }
        let container: MolibooAssetPackContainer
        do { container = try JSONDecoder().decode(MolibooAssetPackContainer.self, from: data) }
        catch { throw MolibooPackageError.corrupt("container") }
        guard container.schemaVersion == MolibooAssetPackContainer.schemaVersion else { throw MolibooPackageError.unsupportedSchema(container.schemaVersion) }
        guard container.packageId == d.packageId, container.version == d.version, container.characterId == d.moliboo.characterId else {
            throw MolibooPackageError.corrupt("container identity")
        }
        guard !container.files.isEmpty, container.files.count <= MolibooPackageLimits.maxFiles else { throw MolibooPackageError.tooLarge }
        var total = 0, paths = Set<String>()
        for f in container.files {
            guard isSafe(path: f.path) else { throw MolibooPackageError.unsafePath(f.path) }
            guard paths.insert(f.path.lowercased()).inserted else { throw MolibooPackageError.corrupt("duplicate \(f.path)") }
            // Bound the decoded size BEFORE decoding (base64 expands 4:3), so a declared-small bomb is rejected cheaply.
            guard f.bytes >= 0, f.bytes <= MolibooPackageLimits.maxFileBytes, f.data.utf8.count <= (f.bytes + 2) / 3 * 4 + 4 else { throw MolibooPackageError.tooLarge }
            total += f.bytes
            guard total <= MolibooPackageLimits.maxDecodedBytes else { throw MolibooPackageError.tooLarge }
        }
        guard container.files.contains(where: { $0.path == "character.json" }) else { throw MolibooPackageError.corrupt("character.json missing") }
        for f in container.files {
            guard let bytes = Data(base64Encoded: f.data), bytes.count == f.bytes, sha256Hex(bytes) == f.sha256 else {
                throw MolibooPackageError.corrupt("file \(f.path)")
            }
        }
        return container
    }

    static func validate(patch p: MolibooCharacterPatch, descriptor d: MolibooPackageDescriptor, registry: MolibooCharacterRegistry?) throws {
        guard p.schemaVersion == MolibooCharacterPatch.schemaVersion else { throw MolibooPackageError.unsupportedSchema(p.schemaVersion) }
        guard p.characterId == d.moliboo.characterId else { throw MolibooPackageError.invalidPatch("characterId") }
        if let registry {
            guard let c = registry.character(id: p.characterId), c.key == p.key else { throw MolibooPackageError.unknownCharacter(p.characterId) }
            if !c.wearable, p.fit != nil { throw MolibooPackageError.invalidPatch("Legends have no wardrobe fit") }
        }
        guard MolibooRegistryValidator.isSemVer(p.assetVersion) else { throw MolibooPackageError.invalidPatch("assetVersion") }
        if let pal = p.palette {
            for h in [pal.mid, pal.accent] + [pal.iris, pal.light, pal.dark, pal.outline].compactMap({ $0 }) where Color(molibooHex: h) == nil {
                throw MolibooPackageError.invalidPatch("colour \(h)")
            }
        }
        if let g = p.glow, Color(molibooHex: g) == nil { throw MolibooPackageError.invalidPatch("glow") }
        if let s = p.size, !((0.5...1.3).contains(s.width) && (0.5...1.3).contains(s.height)) { throw MolibooPackageError.invalidPatch("size") }
        if let n = p.sparkles, !(0...8).contains(n) { throw MolibooPackageError.invalidPatch("sparkles") }
        if let f = p.fit {
            if let v = f.hatScale, !(0.4...1.4).contains(v) { throw MolibooPackageError.invalidPatch("hatScale") }
            if let v = f.hatMaxWidth, !(0.2...0.9).contains(v) { throw MolibooPackageError.invalidPatch("hatMaxWidth") }
            if let v = f.headTopExtra, !(0...0.3).contains(v) { throw MolibooPackageError.invalidPatch("headTopExtra") }
        }
    }
}

extension Color {
    /// `#RRGGBB` only (declarative package data).
    init?(molibooHex hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

// MARK: Disk store (staging, atomic activation, rollback)

struct MolibooPackageIndex: Codable, Equatable, Sendable {
    var packageId: String
    var active: String?
    var previous: String?
    var history: [String]
}

final class MolibooPackageStore: @unchecked Sendable {
    let root: URL
    private let fm = FileManager.default

    init(root: URL? = nil) {
        if let root { self.root = root } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            self.root = base.appendingPathComponent("Modula/Packages/moliboo", isDirectory: true)
        }
    }

    private func safe(_ s: String) -> String { String(s.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0) ? Character($0) : "_" }) }
    func packageDir(_ id: String) -> URL { root.appendingPathComponent(safe(id), isDirectory: true) }
    func versionDir(_ id: String, _ v: String) -> URL { packageDir(id).appendingPathComponent(safe(v), isDirectory: true) }

    func index(_ id: String) -> MolibooPackageIndex {
        let url = packageDir(id).appendingPathComponent("index.json")
        guard let data = try? Data(contentsOf: url), let i = try? JSONDecoder().decode(MolibooPackageIndex.self, from: data) else {
            return MolibooPackageIndex(packageId: id, active: nil, previous: nil, history: [])
        }
        return i
    }

    func writeIndex(_ i: MolibooPackageIndex) throws {
        let dir = packageDir(i.packageId)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(i).write(to: dir.appendingPathComponent("index.json"), options: [.atomic])
    }

    func installedPackageIDs() -> [String] {
        ((try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { fm.fileExists(atPath: $0.appendingPathComponent("index.json").path) }
            .map { index($0.lastPathComponent).packageId }
            .sorted()
    }

    /// Writes a verified container into a fresh staging directory. Nothing outside the package directory is touched.
    func stage(_ c: MolibooAssetPackContainer, descriptor: MolibooPackageDescriptor) throws -> URL {
        let staging = packageDir(c.packageId).appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            for f in c.files {
                guard MolibooPackageValidator.isSafe(path: f.path), let bytes = Data(base64Encoded: f.data) else { throw MolibooPackageError.unsafePath(f.path) }
                let dest = staging.appendingPathComponent(f.path)
                guard dest.standardizedFileURL.path.hasPrefix(staging.standardizedFileURL.path + "/") else { throw MolibooPackageError.unsafePath(f.path) }
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: dest, options: [.atomic])
            }
            try JSONEncoder().encode(descriptor).write(to: staging.appendingPathComponent("descriptor.json"), options: [.atomic])
            return staging
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    /// Moves staging into its immutable version directory, then flips `active` with one atomic index write.
    func activate(staging: URL, packageId: String, version: String) throws -> MolibooPackageIndex {
        let dest = versionDir(packageId, version)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: staging) }   // immutable: same version already present
        else { try fm.moveItem(at: staging, to: dest) }
        var i = index(packageId)
        if i.active != version { i.previous = i.active }
        i.active = version
        if !i.history.contains(version) { i.history.append(version) }
        try writeIndex(i)
        return i
    }

    func rollback(_ id: String) throws -> MolibooPackageIndex {
        var i = index(id)
        guard let prev = i.previous, fm.fileExists(atPath: versionDir(id, prev).path) else { throw MolibooPackageError.nothingToRollBack }
        let broken = i.active
        i.active = prev
        i.previous = nil
        try writeIndex(i)
        if let broken, broken != prev { try? fm.removeItem(at: versionDir(id, broken)); i.history.removeAll { $0 == broken }; try writeIndex(i) }
        return i
    }

    func remove(_ id: String) throws { if fm.fileExists(atPath: packageDir(id).path) { try fm.removeItem(at: packageDir(id)) } }

    func activePatch(_ id: String) -> (MolibooPackageDescriptor, MolibooCharacterPatch)? {
        let i = index(id)
        guard let v = i.active else { return nil }
        let dir = versionDir(id, v)
        guard let dd = try? Data(contentsOf: dir.appendingPathComponent("descriptor.json")),
              let d = try? JSONDecoder().decode(MolibooPackageDescriptor.self, from: dd),
              let pd = try? Data(contentsOf: dir.appendingPathComponent("character.json")),
              let p = try? JSONDecoder().decode(MolibooCharacterPatch.self, from: pd) else { return nil }
        return (d, p)
    }

    func sizeOnDisk() -> Int64 {
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in e { total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return total
    }

    /// Removes abandoned staging directories (interrupted installs).
    func sweepStaging() {
        for pkg in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            for item in (try? fm.contentsOfDirectory(at: pkg, includingPropertiesForKeys: nil)) ?? [] where item.lastPathComponent.hasPrefix(".staging-") {
                try? fm.removeItem(at: item)
            }
        }
    }
}

// MARK: Runtime overlay read by the renderer (lock-protected, lazy, offline)

struct MolibooActivePackage: Equatable, Sendable {
    var packageId: String
    var version: String
    var patch: MolibooCharacterPatch
}

/// Bumped whenever the active package set changes, so mounted figures redraw with new artwork.
/// Only touched on the main thread (bumped by `MolibooPackageRuntime.reload()`, read while SwiftUI evaluates a body).
@Observable
final class MolibooPackageRevision: @unchecked Sendable {
    static let shared = MolibooPackageRevision()
    private(set) var value = 0
    @MainActor func bump() { value += 1 }

    /// Called from the renderer hooks: on the main thread it registers an Observation dependency so any figure body
    /// that resolves a spec or palette redraws when packages change. In Debug it also starts the QA auto-updater when
    /// the app was launched with `-MolibooPackageAutoUpdate` (no-op otherwise). Off the main thread it does nothing.
    func observe() {
        guard Thread.isMainThread else { return }
        _ = value
        #if DEBUG
        MainActor.assumeIsolated { MolibooPackageQAAutoUpdater.startIfRequested() }
        #endif
    }
}

#if DEBUG
/// Debug/QA only: polls the configured QA package source and installs newer signed releases, so artwork changes
/// reach a running simulator build without recompiling. Never compiled into Release.
@MainActor
enum MolibooPackageQAAutoUpdater {
    private static var started = false
    private static var rejected: Set<String> = []

    static func startIfRequested() {
        guard !started else { return }
        started = true
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-MolibooPackageAutoUpdate") else { return }
        var interval = 5.0
        if let i = args.firstIndex(of: "-MolibooPackagePollSeconds"), i + 1 < args.count, let v = Double(args[i + 1]), v >= 1 { interval = v }
        Task { @MainActor in
            let manager = MolibooPackageManager.shared
            packageLog.info("QA auto-update on, source=\(manager.baseURL?.absoluteString ?? "none", privacy: .public)")
            while !Task.isCancelled {
                await manager.refreshCatalog()
                let installed = manager.installedVersions
                for d in manager.latestByPackage.values.sorted(by: { $0.packageId < $1.packageId }) where !rejected.contains(d.id) {
                    let current = installed[d.packageId]
                    guard current.map({ MolibooPackageValidator.compareSemVer(d.version, $0) > 0 }) ?? true else { continue }
                    let ok = await manager.install(d)
                    packageLog.info("QA auto-update \(d.id, privacy: .public): \(ok ? "installed" : "rejected", privacy: .public) \(manager.lastError ?? "", privacy: .public)")
                    if !ok { rejected.insert(d.id) }
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }
}
#endif

final class MolibooPackageRuntime: @unchecked Sendable {
    static let shared = MolibooPackageRuntime()

    private let lock = OSAllocatedUnfairLock<[String: MolibooActivePackage]?>(initialState: nil)
    let store: MolibooPackageStore

    init(store: MolibooPackageStore = MolibooPackageStore()) { self.store = store }

    /// Active packages by character key. First access reads the local index only (no network).
    func active() -> [String: MolibooActivePackage] {
        if let loaded = lock.withLock({ $0 }) { return loaded }
        let fresh = loadFromDisk()
        lock.withLock { if $0 == nil { $0 = fresh } }
        return lock.withLock { $0 ?? [:] }
    }

    func active(for kind: ModulaMascotKind) -> MolibooActivePackage? { active()[kind.rawValue] }

    private func loadFromDisk() -> [String: MolibooActivePackage] {
        var map: [String: MolibooActivePackage] = [:]
        for id in store.installedPackageIDs() {
            guard let (d, p) = store.activePatch(id) else { continue }
            map[p.key] = MolibooActivePackage(packageId: d.packageId, version: d.version, patch: p)
        }
        if !map.isEmpty { packageLog.info("Loaded \(map.count) installed Moliboo packages") }
        return map
    }

    @MainActor func reload() {
        let fresh = loadFromDisk()
        lock.withLock { $0 = fresh }
        MolibooPackageRevision.shared.bump()
    }

    // Renderer hooks: cheap when nothing is installed.
    #if DEBUG
    /// Developer fitting lab only (never Release): live fit overrides keyed by character key.
    private let debugFits = OSAllocatedUnfairLock<[String: MolibooCharacterPatch.Fit]>(initialState: [:])
    func setDebugFit(_ fit: MolibooCharacterPatch.Fit?, for kind: ModulaMascotKind) {
        debugFits.withLock { $0[kind.rawValue] = fit }
    }
    func debugFit(for kind: ModulaMascotKind) -> MolibooCharacterPatch.Fit? { debugFits.withLock { $0[kind.rawValue] } }
    #endif

    func patchedSpec(_ kind: ModulaMascotKind, _ base: MolibooSpec?) -> MolibooSpec? {
        MolibooPackageRevision.shared.observe()
        #if DEBUG
        if var spec = base, let f = debugFits.withLock({ $0[kind.rawValue] }) {
            if let v = f.hatScale { spec.hatScale = CGFloat(v) }
            if let v = f.hatMaxWidth { spec.hatMaxWidth = CGFloat(v) }
            if let v = f.headTopExtra { spec.headTopExtra = CGFloat(v) }
            return spec
        }
        #endif
        guard var spec = base, let p = active(for: kind)?.patch else { return base }
        if let pal = p.palette, let palette = ModulaMascotKind.Palette(patch: pal) { spec.palette = palette }
        if let s = p.size { spec.size = CGSize(width: s.width, height: s.height) }
        if let remove = p.removeParts, !remove.isEmpty { spec.parts.removeAll { remove.contains($0.patchName) } }
        if let g = p.glow.flatMap(Color.init(molibooHex:)) {
            spec.parts.removeAll { $0.patchName == "glow" }
            spec.parts.insert(.glow(g), at: 0)
        }
        if let n = p.sparkles {
            spec.parts.removeAll { $0.patchName == "sparkles" }
            if n > 0 { spec.parts.append(.sparkles(n)) }
        }
        if let form = p.form { spec.form = form }
        if let f = p.fit {
            if let v = f.hatScale { spec.hatScale = CGFloat(v) }
            if let v = f.hatMaxWidth { spec.hatMaxWidth = CGFloat(v) }
            if let v = f.headTopExtra { spec.headTopExtra = CGFloat(v) }
        }
        return spec
    }

    func patchedPalette(_ kind: ModulaMascotKind) -> ModulaMascotKind.Palette? {
        guard kind.spec == nil, let pal = active(for: kind)?.patch.palette else { return nil }   // spec kinds take it via patchedSpec
        return ModulaMascotKind.Palette(patch: pal)
    }
}

extension MolibooPart {
    /// Case name used by package patches (`removeParts`).
    var patchName: String {
        let d = String(describing: self)
        return String(d.prefix { $0 != "(" })
    }
}

extension ModulaMascotKind.Palette {
    init?(patch p: MolibooCharacterPatch.PaletteHex) {
        guard let mid = Color(molibooHex: p.mid), let accent = Color(molibooHex: p.accent) else { return nil }
        self = .spec(mid, accent: accent, iris: p.iris.flatMap(Color.init(molibooHex:)) ?? Color(red: 0.16, green: 0.12, blue: 0.24),
                     light: p.light.flatMap(Color.init(molibooHex:)), dark: p.dark.flatMap(Color.init(molibooHex:)),
                     outline: p.outline.flatMap(Color.init(molibooHex:)))
    }
}

// MARK: Manager (download, install, update, rollback, remove)

@MainActor
@Observable
final class MolibooPackageManager {
    enum Status: Equatable { case idle, checking, downloading(String), installed(String), failed(String), rolledBack(String) }

    static let shared = MolibooPackageManager()

    private(set) var catalog: [MolibooPackageDescriptor] = []
    private(set) var status: Status = .idle
    private(set) var lastError: String?
    var baseURL: URL?

    @ObservationIgnored let runtime: MolibooPackageRuntime
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored var policy: () -> ModuleTrustPolicy = { ModuleTrustPolicy.current }
    @ObservationIgnored var hostVersion: String = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    @ObservationIgnored var registry: MolibooCharacterRegistry? = MolibooRegistryStore.bundled
    /// Test hook: health check after activation (default decodes the patch back from disk and renders its spec).
    @ObservationIgnored var healthCheck: ((MolibooCharacterPatch) -> Bool)?

    init(runtime: MolibooPackageRuntime = .shared, session: URLSession = .shared, baseURL: URL? = MolibooPackageManager.configuredBaseURL) {
        self.runtime = runtime
        self.session = session
        self.baseURL = baseURL
        runtime.store.sweepStaging()
    }

    /// The package source. GreenField has no public Moliboo endpoint yet, so only Debug builds read a QA source from
    /// `-MolibooPackageBaseURL <url>` or `MOLIBOO_PACKAGE_BASE_URL`; Release has none and stays on the built-in art.
    nonisolated static var configuredBaseURL: URL? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-MolibooPackageBaseURL"), i + 1 < args.count, let u = URL(string: args[i + 1]) { return u }
        if let s = ProcessInfo.processInfo.environment["MOLIBOO_PACKAGE_BASE_URL"], let u = URL(string: s) { return u }
        if let s = UserDefaults.standard.string(forKey: "dev.moliboo.packageBaseURL"), let u = URL(string: s) { return u }
        #endif
        return nil
    }

    var installedVersions: [String: String] {
        Dictionary(uniqueKeysWithValues: runtime.store.installedPackageIDs().compactMap { id in runtime.store.index(id).active.map { (id, $0) } })
    }

    func storageBytes() -> Int64 { runtime.store.sizeOnDisk() }

    func refreshCatalog() async {
        guard let baseURL else { status = .failed("No package source"); lastError = "No package source is configured."; return }
        status = .checking
        do {
            // Always revalidate: a heuristically cached catalogue would hide new releases until the cache expires.
            var req = URLRequest(url: baseURL.appendingPathComponent("catalog.json"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            let (data, resp) = try await session.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200, data.count <= 1_000_000 else { throw MolibooPackageError.network("catalogue") }
            let cat = try JSONDecoder().decode(MolibooPackageCatalog.self, from: data)
            guard cat.schemaVersion == MolibooPackageCatalog.schemaVersion else { throw MolibooPackageError.unsupportedSchema(cat.schemaVersion) }
            catalog = cat.packages
            status = .idle
            lastError = nil
        } catch {
            status = .failed("catalogue")
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Updates available for installed packages (newer version in the catalogue).
    var updates: [MolibooPackageDescriptor] {
        let installed = installedVersions
        return latestByPackage.values.filter { d in installed[d.packageId].map { MolibooPackageValidator.compareSemVer(d.version, $0) > 0 } ?? false }
            .sorted { $0.packageId < $1.packageId }
    }

    var latestByPackage: [String: MolibooPackageDescriptor] {
        Dictionary(catalog.map { ($0.packageId, $0) }, uniquingKeysWith: { a, b in MolibooPackageValidator.compareSemVer(a.version, b.version) >= 0 ? a : b })
    }

    @discardableResult
    func install(_ d: MolibooPackageDescriptor) async -> Bool {
        do {
            let order = try MolibooPackageValidator.installOrder(for: d, catalog: catalog, installed: Set(installedVersions.keys))
            for item in order { try await installOne(item) }
            status = .installed("\(d.packageId)@\(d.version)")
            lastError = nil
            return true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            packageLog.error("Install \(d.id, privacy: .public) failed: \(message, privacy: .public)")
            lastError = message
            if case .rolledBack = status {} else { status = .failed(message) }
            return false
        }
    }

    private func installOne(_ d: MolibooPackageDescriptor) async throws {
        try MolibooPackageValidator.validate(descriptor: d, registry: registry, hostVersion: hostVersion)
        status = .downloading(d.id)
        let data = try await download(d)
        let container = try MolibooPackageValidator.verify(artifact: data, descriptor: d, policy: policy())
        guard let file = container.files.first(where: { $0.path == "character.json" }), let raw = Data(base64Encoded: file.data) else {
            throw MolibooPackageError.corrupt("character.json")
        }
        let patch: MolibooCharacterPatch
        do { patch = try JSONDecoder().decode(MolibooCharacterPatch.self, from: raw) } catch { throw MolibooPackageError.invalidPatch("decode") }
        try MolibooPackageValidator.validate(patch: patch, descriptor: d, registry: registry)
        let store = runtime.store
        let staging = try store.stage(container, descriptor: d)
        _ = try store.activate(staging: staging, packageId: d.packageId, version: d.version)
        // Post-activation health check: the activated files must decode and render; otherwise restore the last good one.
        let healthy = store.activePatch(d.packageId).map { healthCheck?($0.1) ?? Self.renders($0.1) } ?? false
        if !healthy {
            if (try? store.rollback(d.packageId)) == nil { try? store.remove(d.packageId) }
            runtime.reload()
            status = .rolledBack(d.packageId)
            throw MolibooPackageError.invalidPatch("activation health check failed; previous version restored")
        }
        runtime.reload()
    }

    private func download(_ d: MolibooPackageDescriptor) async throws -> Data {
        let path = d.artifact.download.pathOrUrl
        let url: URL?
        if path.hasPrefix("https://") || path.hasPrefix("http://") { url = URL(string: path) }
        else { url = baseURL.map { $0.appendingPathComponent(path) } }
        guard let url else { throw MolibooPackageError.network("no download location") }
        #if !DEBUG
        guard url.scheme == "https" else { throw MolibooPackageError.network("insecure location") }
        #endif
        var req = URLRequest(url: url)
        req.timeoutInterval = 30
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { throw MolibooPackageError.network("HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)") }
        guard http.expectedContentLength <= Int64(MolibooPackageLimits.maxArtifactBytes), data.count <= MolibooPackageLimits.maxArtifactBytes else {
            throw MolibooPackageError.tooLarge
        }
        return data
    }

    private static func renders(_ p: MolibooCharacterPatch) -> Bool {
        guard let kind = ModulaMascotKind(rawValue: p.key) else { return false }
        if let pal = p.palette, ModulaMascotKind.Palette(patch: pal) == nil { return false }
        return kind.palette.mid != Color.clear
    }

    func rollback(_ packageId: String) {
        do {
            let i = try runtime.store.rollback(packageId)
            runtime.reload()
            status = .rolledBack("\(packageId)@\(i.active ?? "built-in")")
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            status = .failed(lastError ?? "rollback")
        }
    }

    /// Reclaims storage. The built-in artwork remains, so the character never disappears.
    func remove(_ packageId: String) {
        try? runtime.store.remove(packageId)
        runtime.reload()
        status = .idle
    }
}
