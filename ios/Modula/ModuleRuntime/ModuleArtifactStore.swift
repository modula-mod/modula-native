import Foundation
import CryptoKit

enum ModuleCacheSlot: String, Codable, Sendable {
    case active = "ACTIVE"
    case previousGood = "PREVIOUS_GOOD"
    case staged = "STAGED"
}

struct ModuleCachedRelease: Sendable {
    var moduleId: String
    var version: String
    var releaseId: String
    var accountID: String
    var frontendSha256: String
    var frontendMediaType: String
    var gameSha256: String?
    var runtimeSha256: String?
    var hostManifest: ModuleManifest
    var descriptor: ModuleInstallDescriptor?
    var slot: ModuleCacheSlot
    var directory: URL
}

struct ModuleCacheIndex: Codable, Equatable, Sendable {
    var accountID: String
    var moduleId: String
    var activeReleaseId: String?
    var previousGoodReleaseId: String?
    var stagedReleaseId: String?
    var lastAuditReason: String?
}

/// Per-account immutable module artifact cache. No bearer token is stored with bytes.
final class ModuleArtifactStore: @unchecked Sendable {
    let root: URL
    private let fileManager: FileManager

    init(root: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let root {
            self.root = root
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.root = base.appendingPathComponent("Modula/ModuleCache", isDirectory: true)
        }
    }

    func moduleRoot(accountID: String, moduleId: String) -> URL {
        root.appendingPathComponent(safe(accountID), isDirectory: true)
            .appendingPathComponent(safe(moduleId), isDirectory: true)
    }

    func slotURL(accountID: String, moduleId: String, slot: ModuleCacheSlot) -> URL {
        moduleRoot(accountID: accountID, moduleId: moduleId)
            .appendingPathComponent(slot.rawValue, isDirectory: true)
    }

    func index(accountID: String, moduleId: String) -> ModuleCacheIndex {
        let url = moduleRoot(accountID: accountID, moduleId: moduleId).appendingPathComponent("index.json")
        guard let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode(ModuleCacheIndex.self, from: data) else {
            return ModuleCacheIndex(accountID: accountID, moduleId: moduleId)
        }
        return index
    }

    func writeIndex(_ index: ModuleCacheIndex) throws {
        let directory = moduleRoot(accountID: index.accountID, moduleId: index.moduleId)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(index)
        try atomicWrite(data, to: directory.appendingPathComponent("index.json"))
    }

    func release(in slot: ModuleCacheSlot, accountID: String, moduleId: String) -> ModuleCachedRelease? {
        let directory = slotURL(accountID: accountID, moduleId: moduleId, slot: slot)
        let metaURL = directory.appendingPathComponent("release.json")
        guard let data = try? Data(contentsOf: metaURL),
              let json = try? JSONDecoder().decode(JSONValue.self, from: data),
              let version = json["version"]?.string,
              let releaseId = json["releaseId"]?.string,
              let frontendSha256 = json["frontendSha256"]?.string,
              let mediaType = json["frontendMediaType"]?.string,
              let manifestJSON = json["hostManifest"],
              let manifestData = try? JSONEncoder().encode(manifestJSON),
              let manifest = try? JSONDecoder().decode(ModuleManifest.self, from: manifestData)
        else { return nil }
        var descriptor: ModuleInstallDescriptor?
        if let raw = json["descriptor"] {
            descriptor = ModuleInstallDescriptor(json: raw)
        }
        return ModuleCachedRelease(
            moduleId: moduleId, version: version, releaseId: releaseId, accountID: accountID,
            frontendSha256: frontendSha256, frontendMediaType: mediaType,
            gameSha256: json["gameSha256"]?.string, runtimeSha256: json["runtimeSha256"]?.string, hostManifest: manifest,
            descriptor: descriptor, slot: slot, directory: directory
        )
    }

    func frontendData(for release: ModuleCachedRelease) throws -> Data {
        let url = release.directory.appendingPathComponent("frontend.manifest.json")
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == release.frontendSha256 else {
            throw ModuleActivationError.digestMismatch("frontend")
        }
        return data
    }

    /// Writes verified bytes into STAGED. Never writes into ACTIVE in place.
    func stage(accountID: String, moduleId: String, version: String, releaseId: String,
               frontend: Data, frontendSha256: String, mediaType: String,
               hostManifest: ModuleManifest, descriptor: ModuleInstallDescriptor?,
               game: WebGamePackage? = nil, runtimeSha256: String? = nil) throws {
        let expected = SHA256.hash(data: frontend).map { String(format: "%02x", $0) }.joined()
        guard expected == frontendSha256 else { throw ModuleActivationError.digestMismatch("frontend") }
        if let traversal = Self.unsafePath(in: frontend) { throw ModuleActivationError.pathTraversal(traversal) }
        let staged = slotURL(accountID: accountID, moduleId: moduleId, slot: .staged)
        if fileManager.fileExists(atPath: staged.path) {
            try fileManager.removeItem(at: staged)
        }
        let staging = staged.appendingPathExtension("partial")
        if fileManager.fileExists(atPath: staging.path) { try fileManager.removeItem(at: staging) }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        try atomicWrite(frontend, to: staging.appendingPathComponent("frontend.manifest.json"))
        if let game {
            try atomicWrite(game.archive, to: staging.appendingPathComponent("game.tgz"))
            _ = try game.install(in: staging.appendingPathComponent("Game", isDirectory: true))
        }
        var meta: [String: JSONValue] = [
            "moduleId": .string(moduleId),
            "version": .string(version),
            "releaseId": .string(releaseId),
            "frontendSha256": .string(frontendSha256),
            "frontendMediaType": .string(mediaType),
            "hostManifest": try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(hostManifest)),
        ]
        if let descriptor { meta["descriptor"] = descriptor.raw }
        if let game { meta["gameSha256"] = .string(game.sha256) }
        if let runtimeSha256 { meta["runtimeSha256"] = .string(runtimeSha256) }
        try atomicWrite(JSONEncoder().encode(JSONValue.object(meta)), to: staging.appendingPathComponent("release.json"))
        try fileManager.moveItem(at: staging, to: staged)
        var current = index(accountID: accountID, moduleId: moduleId)
        current.stagedReleaseId = releaseId
        try writeIndex(current)
    }

    func verifiedGameEntry(for release: ModuleCachedRelease) throws -> URL {
        guard let digest = release.gameSha256 else { throw WebGamePackageError.invalid("game metadata") }
        if let runtimeSha256 = release.runtimeSha256 {
            _ = try SharedWebRuntimeStore(moduleCacheRoot: root).verifiedEngine(sha256: runtimeSha256)
        }
        let archive = try Data(contentsOf: release.directory.appendingPathComponent("game.tgz"))
        let trusted = try WebGamePackage(archive: archive, expectedSha256: digest)
        return try WebGamePackage.verifyInstalled(
            at: release.directory.appendingPathComponent("Game/\(digest)", isDirectory: true),
            expectedSha256: digest, trustedFiles: trusted.files
        )
    }

    #if DEBUG
    /// Writes STAGED bytes whose declared digest does not match. Release builds cannot do this.
    func stageDeclaredDigestMismatch(
        accountID: String, moduleId: String, version: String, releaseId: String,
        frontend: Data, declaredSha256: String, hostManifest: ModuleManifest
    ) throws {
        if let traversal = Self.unsafePath(in: frontend) { throw ModuleActivationError.pathTraversal(traversal) }
        let staged = slotURL(accountID: accountID, moduleId: moduleId, slot: .staged)
        if fileManager.fileExists(atPath: staged.path) { try fileManager.removeItem(at: staged) }
        try fileManager.createDirectory(at: staged, withIntermediateDirectories: true)
        try atomicWrite(frontend, to: staged.appendingPathComponent("frontend.manifest.json"))
        let meta: [String: JSONValue] = [
            "moduleId": .string(moduleId),
            "version": .string(version),
            "releaseId": .string(releaseId),
            "frontendSha256": .string(declaredSha256),
            "frontendMediaType": .string(ProductUIDocument.mediaType),
            "hostManifest": try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(hostManifest)),
        ]
        try atomicWrite(JSONEncoder().encode(JSONValue.object(meta)), to: staged.appendingPathComponent("release.json"))
        var current = index(accountID: accountID, moduleId: moduleId)
        current.stagedReleaseId = releaseId
        try writeIndex(current)
    }
    #endif

    /// ACTIVE ← STAGED, previous ACTIVE becomes PREVIOUS_GOOD.
    func activateStaged(accountID: String, moduleId: String) throws -> ModuleCachedRelease {
        let staged = slotURL(accountID: accountID, moduleId: moduleId, slot: .staged)
        let active = slotURL(accountID: accountID, moduleId: moduleId, slot: .active)
        let previous = slotURL(accountID: accountID, moduleId: moduleId, slot: .previousGood)
        guard fileManager.fileExists(atPath: staged.path) else { throw ModuleActivationError.missingStaged }
        if fileManager.fileExists(atPath: previous.path) { try fileManager.removeItem(at: previous) }
        if fileManager.fileExists(atPath: active.path) {
            try fileManager.moveItem(at: active, to: previous)
        }
        try fileManager.moveItem(at: staged, to: active)
        guard let release = release(in: .active, accountID: accountID, moduleId: moduleId) else {
            try rollbackToPreviousGood(accountID: accountID, moduleId: moduleId)
            throw ModuleActivationError.activationHealth
        }
        var current = index(accountID: accountID, moduleId: moduleId)
        current.previousGoodReleaseId = current.activeReleaseId
        current.activeReleaseId = release.releaseId
        current.stagedReleaseId = nil
        try writeIndex(current)
        return release
    }

    @discardableResult
    func rollbackToPreviousGood(accountID: String, moduleId: String) throws -> ModuleCachedRelease? {
        let active = slotURL(accountID: accountID, moduleId: moduleId, slot: .active)
        let previous = slotURL(accountID: accountID, moduleId: moduleId, slot: .previousGood)
        guard fileManager.fileExists(atPath: previous.path) else { return release(in: .active, accountID: accountID, moduleId: moduleId) }
        let broken = slotURL(accountID: accountID, moduleId: moduleId, slot: .staged)
            .deletingLastPathComponent().appendingPathComponent("BROKEN-\(UUID().uuidString)", isDirectory: true)
        if fileManager.fileExists(atPath: active.path) {
            try fileManager.moveItem(at: active, to: broken)
        }
        try fileManager.moveItem(at: previous, to: active)
        var current = index(accountID: accountID, moduleId: moduleId)
        current.activeReleaseId = release(in: .active, accountID: accountID, moduleId: moduleId)?.releaseId
        current.previousGoodReleaseId = nil
        try writeIndex(current)
        return release(in: .active, accountID: accountID, moduleId: moduleId)
    }

    /// Drops one account's cached releases for a module. Does not touch any other module or account.
    func removeModule(accountID: String, moduleId: String) throws {
        let directory = moduleRoot(accountID: accountID, moduleId: moduleId)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        if WebGameSessionPins.shared.contains(directory) { throw ModuleActivationError.activeSession }
        try fileManager.removeItem(at: directory)
    }

    func purgeAccount(_ accountID: String) throws {
        let url = root.appendingPathComponent(safe(accountID), isDirectory: true)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    private func atomicWrite(_ data: Data, to url: URL) throws {
        let temp = url.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        try fileManager.moveItem(at: temp, to: url)
    }

    private func safe(_ value: String) -> String {
        value.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "..", with: "_")
    }

    static func unsafePath(in data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        if text.contains("../") || text.contains("..\\") { return ".." }
        return nil
    }
}

/// Shared immutable runtime bytes live inside the existing module cache. Ownership
/// is derived from durable STAGED/ACTIVE/PREVIOUS_GOOD release pointers, so a
/// force quit between an update and a cleanup cannot erase rollback bytes.
final class SharedWebRuntimeStore {
    let moduleCacheRoot: URL
    private let manager: FileManager
    private var runtimesRoot: URL { moduleCacheRoot.appendingPathComponent("SharedWebRuntimes", isDirectory: true) }

    init(moduleCacheRoot: URL, fileManager: FileManager = .default) {
        self.moduleCacheRoot = moduleCacheRoot
        manager = fileManager
    }

    func installVerified(_ package: WebRuntimePackage) throws {
        let destination = runtimesRoot.appendingPathComponent(package.sha256, isDirectory: true)
        if manager.fileExists(atPath: destination.path) {
            if (try? verifiedEngine(sha256: package.sha256)) != nil { return }
        }
        try manager.createDirectory(at: runtimesRoot, withIntermediateDirectories: true)
        let partial = runtimesRoot.appendingPathComponent("\(package.sha256).partial-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: partial, withIntermediateDirectories: true)
        do {
            try package.archive.write(to: partial.appendingPathComponent("artifact.tgz"), options: .atomic)
            try package.engine.write(to: partial.appendingPathComponent("engine.mjs"), options: .atomic)
            if manager.fileExists(atPath: destination.path) {
                let quarantined = runtimesRoot.appendingPathComponent("\(package.sha256).corrupt-\(UUID().uuidString)")
                try manager.moveItem(at: destination, to: quarantined)
                do {
                    try manager.moveItem(at: partial, to: destination)
                    try? manager.removeItem(at: quarantined)
                } catch {
                    if !manager.fileExists(atPath: destination.path) { try? manager.moveItem(at: quarantined, to: destination) }
                    throw error
                }
            } else {
                try manager.moveItem(at: partial, to: destination)
            }
        } catch {
            try? manager.removeItem(at: partial)
            if manager.fileExists(atPath: destination.path) {
                _ = try verifiedEngine(sha256: package.sha256)
                return
            }
            throw error
        }
    }

    func verifiedEngine(sha256: String) throws -> Data {
        guard InstallDescriptorVerifier.isHex64(sha256) else { throw WebGamePackageError.invalid("runtime digest") }
        let directory = runtimesRoot.appendingPathComponent(sha256, isDirectory: true)
        let directoryValues = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard directoryValues.isDirectory == true, directoryValues.isSymbolicLink != true else {
            throw WebGamePackageError.invalid("runtime directory")
        }
        let members = try manager.contentsOfDirectory(atPath: directory.path)
        guard Set(members) == Set(["artifact.tgz", "engine.mjs"]) else { throw WebGamePackageError.invalid("runtime members") }
        for name in members {
            let values = try directory.appendingPathComponent(name).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw WebGamePackageError.invalid("runtime member type")
            }
        }
        let archive = try Data(contentsOf: directory.appendingPathComponent("artifact.tgz"))
        let package = try WebRuntimePackage(archive: archive, expectedSha256: sha256)
        guard try Data(contentsOf: directory.appendingPathComponent("engine.mjs")) == package.engine else {
            throw WebGamePackageError.invalid("installed runtime digest")
        }
        return package.engine
    }

    func installedDigests() -> [String] {
        (try? manager.contentsOfDirectory(atPath: runtimesRoot.path))?.filter(InstallDescriptorVerifier.isHex64).sorted() ?? []
    }

    /// Durable ownership is recovered from release slots rather than a mutable
    /// reference count. Callers add running-session and in-progress pins.
    func protectedDigests(additionalPins: Set<String> = []) -> Set<String> {
        var protected = additionalPins.union(WebRuntimeSessionPins.shared.digests)
        guard let accounts = try? manager.contentsOfDirectory(at: moduleCacheRoot, includingPropertiesForKeys: [.isDirectoryKey]) else { return protected }
        for account in accounts where account.lastPathComponent != "SharedWebRuntimes" {
            guard let modules = try? manager.contentsOfDirectory(at: account, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for module in modules {
                for slot in [ModuleCacheSlot.active, .staged, .previousGood] {
                    let slotRoot = module.appendingPathComponent(slot.rawValue)
                    guard manager.fileExists(atPath: slotRoot.path) else { continue }
                    let meta = slotRoot.appendingPathComponent("release.json")
                    guard let data = try? Data(contentsOf: meta),
                          let json = try? JSONDecoder().decode(JSONValue.self, from: data) else {
                        // An interrupted or corrupt active/rollback slot must
                        // never make a dependency appear unowned.
                        return protected.union(installedDigests())
                    }
                    if let digest = json["runtimeSha256"]?.string {
                        guard InstallDescriptorVerifier.isHex64(digest) else {
                            return protected.union(installedDigests())
                        }
                        protected.insert(digest)
                    }
                }
            }
        }
        return protected
    }

    @discardableResult
    func reclaimUnused(additionalPins: Set<String> = []) throws -> [String] {
        let protected = protectedDigests(additionalPins: additionalPins)
        var removed: [String] = []
        for digest in installedDigests() where !protected.contains(digest) {
            try manager.removeItem(at: runtimesRoot.appendingPathComponent(digest, isDirectory: true))
            removed.append(digest)
        }
        return removed
    }
}

/// The scheme handler retains a lease for each live WKWebView. Reclamation
/// consults these process-local leases in addition to the durable release slots.
final class WebRuntimeSessionPin {
    let digest: String
    init(_ digest: String) {
        self.digest = digest
        WebRuntimeSessionPins.shared.acquire(digest)
    }
    deinit { WebRuntimeSessionPins.shared.release(digest) }
}

final class WebRuntimeSessionPins: @unchecked Sendable {
    static let shared = WebRuntimeSessionPins()
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    var digests: Set<String> {
        lock.lock(); defer { lock.unlock() }
        return Set(counts.keys)
    }

    func acquire(_ digest: String) {
        lock.lock(); defer { lock.unlock() }
        counts[digest, default: 0] += 1
    }

    func release(_ digest: String) {
        lock.lock(); defer { lock.unlock() }
        let remaining = (counts[digest] ?? 1) - 1
        if remaining <= 0 { counts.removeValue(forKey: digest) }
        else { counts[digest] = remaining }
    }
}

final class WebGameSessionPin {
    let moduleRoot: URL
    init(_ moduleRoot: URL) {
        self.moduleRoot = moduleRoot
        WebGameSessionPins.shared.acquire(moduleRoot)
    }
    deinit { WebGameSessionPins.shared.release(moduleRoot) }
}

final class WebGameSessionPins: @unchecked Sendable {
    static let shared = WebGameSessionPins()
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    func acquire(_ root: URL) {
        lock.lock(); defer { lock.unlock() }
        counts[root.standardizedFileURL.path, default: 0] += 1
    }
    func release(_ root: URL) {
        lock.lock(); defer { lock.unlock() }
        let key = root.standardizedFileURL.path
        let count = (counts[key] ?? 1) - 1
        if count <= 0 { counts.removeValue(forKey: key) }
        else { counts[key] = count }
    }
    func contains(_ root: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return counts[root.standardizedFileURL.path] != nil
    }
}

enum ModuleActivationError: Error, Equatable, LocalizedError {
    case digestMismatch(String)
    case missingStaged
    case activationHealth
    case pathTraversal(String)
    case untrusted
    case revoked
    case incompatible
    case permissionReviewRequired
    case wrongAccount
    case activeSession

    var errorDescription: String? {
        switch self {
        case .digestMismatch(let field): "The \(field) digest did not match the verified release."
        case .missingStaged: "There is no staged module release to activate."
        case .activationHealth: "The staged release failed its activation health check."
        case .pathTraversal: "The module package contained an unsafe path."
        case .untrusted: "This release is not trusted."
        case .revoked: "This release has been revoked."
        case .incompatible: "This module is not compatible with this version of Modula."
        case .permissionReviewRequired: "This release needs a permission review before it can open."
        case .wrongAccount: "This cached module belongs to another account."
        case .activeSession: "Close the running game before removing its download."
        }
    }
}
