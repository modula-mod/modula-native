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
            frontendSha256: frontendSha256, frontendMediaType: mediaType, hostManifest: manifest,
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
               hostManifest: ModuleManifest, descriptor: ModuleInstallDescriptor?) throws {
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
        var meta: [String: JSONValue] = [
            "moduleId": .string(moduleId),
            "version": .string(version),
            "releaseId": .string(releaseId),
            "frontendSha256": .string(frontendSha256),
            "frontendMediaType": .string(mediaType),
            "hostManifest": try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(hostManifest)),
        ]
        if let descriptor { meta["descriptor"] = descriptor.raw }
        try atomicWrite(JSONEncoder().encode(JSONValue.object(meta)), to: staging.appendingPathComponent("release.json"))
        try fileManager.moveItem(at: staging, to: staged)
        var current = index(accountID: accountID, moduleId: moduleId)
        current.stagedReleaseId = releaseId
        try writeIndex(current)
    }

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
        }
    }
}
