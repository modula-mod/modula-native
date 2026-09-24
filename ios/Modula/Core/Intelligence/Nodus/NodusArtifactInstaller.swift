import CryptoKit
import Foundation

enum NodusArtifactError: Error, Sendable, Equatable {
    case invalidManifest
    case unsupportedManifest
    case missingFile(String)
    case hashMismatch(String)
    case unexpectedFile(String)
    case symbolicLink(String)
    case artifactHashMismatch
    case unexpectedArtifactHash
}

enum NodusModelStage: String, Sendable, Equatable, Codable, CaseIterable {
    case experimentalCandidate
    case candidate
    case accepted
    case quarantined

    var displayName: String {
        switch self {
        case .experimentalCandidate: "Experimental candidate"
        case .candidate: "Candidate"
        case .accepted: "Accepted"
        case .quarantined: "Quarantined"
        }
    }
}

struct NodusModelIdentity: Sendable, Equatable {
    let id: String
    let displayName: String
    let stage: NodusModelStage
    let shippingAllowed: Bool
    let baseModel: String
    let baseRevision: String
    let quantization: String
    let runtimeFormat: String
}

struct NodusExperimentalManifest: Sendable, Equatable, Codable {
    static let fileName = "nodus-r7-experimental.json"

    let schemaVersion: Int
    let id: String
    let displayName: String
    let stage: NodusModelStage
    let shippingAllowed: Bool
    let providerID: String
    let baseModel: String
    let baseRevision: String
    let adapterSource: String
    let adapterSHA256: String
    let trainingRun: String
    let datasetRevision: String
    let knownQualityResults: [String: Double]
    let createdAt: String
    let fusedSHA256: String
    let quantizedSHA256: String
    let runtimeFormat: String
    let quantization: String
    let knownFailedPromotionGates: [String]
    let files: [String: String]

    var identity: NodusModelIdentity {
        NodusModelIdentity(
            id: id,
            displayName: displayName,
            stage: stage,
            shippingAllowed: shippingAllowed,
            baseModel: baseModel,
            baseRevision: baseRevision,
            quantization: quantization,
            runtimeFormat: runtimeFormat
        )
    }

    static func load(from directory: URL) throws -> Self {
        do {
            return try JSONDecoder().decode(
                Self.self,
                from: Data(contentsOf: directory.appending(path: fileName))
            )
        } catch {
            throw NodusArtifactError.invalidManifest
        }
    }

    func verify(in directory: URL) throws {
        guard schemaVersion == 1,
              stage == .experimentalCandidate,
              shippingAllowed == false,
              providerID == NodusIntelligenceProvider.providerID,
              runtimeFormat == "mlx",
              quantization.hasPrefix("4-bit") else {
            throw NodusArtifactError.unsupportedManifest
        }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else { throw NodusArtifactError.invalidManifest }
        let directoryPath = directory.standardizedFileURL.path
        var actualFiles = Set<String>()
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: keys)
            let path = file.standardizedFileURL.path
            guard path.hasPrefix(directoryPath + "/") else { throw NodusArtifactError.invalidManifest }
            let relative = String(path.dropFirst(directoryPath.count + 1))
            if values.isSymbolicLink == true { throw NodusArtifactError.symbolicLink(relative) }
            if values.isRegularFile == true, relative != Self.fileName { actualFiles.insert(relative) }
        }
        guard actualFiles == Set(files.keys) else {
            let mismatch = actualFiles.symmetricDifference(Set(files.keys)).sorted().first ?? "unknown"
            throw NodusArtifactError.unexpectedFile(mismatch)
        }
        for (relative, expectedHash) in files {
            guard !relative.contains(".."), !relative.hasPrefix("/") else {
                throw NodusArtifactError.invalidManifest
            }
            let file = directory.appending(path: relative)
            guard FileManager.default.fileExists(atPath: file.path) else {
                throw NodusArtifactError.missingFile(relative)
            }
            guard try Self.sha256(file) == expectedHash else {
                throw NodusArtifactError.hashMismatch(relative)
            }
        }
        let canonical = Data(
            files.keys.sorted().map { "\($0)\0\(files[$0]!)\n" }.joined().utf8
        )
        guard Self.sha256(canonical) == quantizedSHA256 else {
            throw NodusArtifactError.artifactHashMismatch
        }
    }

    private static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            digest.update(data: data)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct NodusModelManifest: Sendable, Equatable, Codable {
    let schemaVersion: Int
    let nodusVersion: String
    let parameters: Int
    let baseModel: String
    let baseRevision: String
    let license: String
    let fineTuningMethod: String
    let datasetRevision: String
    let evalSuiteRevision: String
    let quantization: String
    let artifactHash: String
    let trainingDate: String
    let knowledgeProvenance: [String]
    let files: [String: String]
}

actor NodusArtifactInstaller {
    private let root: URL

    init(root: URL? = nil) {
        if let root { self.root = root }
        else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.root = support.appending(path: "Modula/Nodus/models")
        }
    }

    func installedManifest() throws -> NodusModelManifest? {
        let url = root.appending(path: "accepted/nodus-manifest.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Self.decodeManifest(at: url)
    }

    func installedSizeBytes() throws -> Int64 {
        let accepted = root.appending(path: "accepted")
        guard let enumerator = FileManager.default.enumerator(
            at: accepted, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += Int64((try file.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
        }
        return total
    }

    /// Developer-controlled local installation. Downloading is performed by an explicit
    /// developer tool; native verifies every file before atomic promotion into `accepted`.
    func installVerifiedArtifact(
        from source: URL,
        expectedArtifactHash: String
    ) throws -> NodusModelManifest {
        let manifest = try Self.decodeManifest(at: source.appending(path: "nodus-manifest.json"))
        guard expectedArtifactHash.hasPrefix("sha256:"),
              expectedArtifactHash.count == 71,
              manifest.artifactHash == expectedArtifactHash else {
            throw NodusArtifactError.unexpectedArtifactHash
        }
        try Self.verify(manifest: manifest, in: source)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appending(path: "staging-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: source, to: staging)
        try Self.verify(manifest: manifest, in: staging)
        let accepted = root.appending(path: "accepted")
        let previous = root.appending(path: "previous")
        if FileManager.default.fileExists(atPath: previous.path) { try FileManager.default.removeItem(at: previous) }
        if FileManager.default.fileExists(atPath: accepted.path) { try FileManager.default.moveItem(at: accepted, to: previous) }
        try FileManager.default.moveItem(at: staging, to: accepted)
        return manifest
    }

    func deleteAcceptedArtifact() throws {
        let accepted = root.appending(path: "accepted")
        if FileManager.default.fileExists(atPath: accepted.path) { try FileManager.default.removeItem(at: accepted) }
    }

    @discardableResult
    func rollbackToPreviousArtifact() throws -> Bool {
        let accepted = root.appending(path: "accepted")
        let previous = root.appending(path: "previous")
        guard FileManager.default.fileExists(atPath: previous.path) else { return false }
        let displaced = root.appending(path: "rollback-\(UUID().uuidString)")
        if FileManager.default.fileExists(atPath: accepted.path) {
            try FileManager.default.moveItem(at: accepted, to: displaced)
        }
        do {
            try FileManager.default.moveItem(at: previous, to: accepted)
            if FileManager.default.fileExists(atPath: displaced.path) {
                try FileManager.default.moveItem(at: displaced, to: previous)
            }
            return true
        } catch {
            if FileManager.default.fileExists(atPath: displaced.path),
               !FileManager.default.fileExists(atPath: accepted.path) {
                try? FileManager.default.moveItem(at: displaced, to: accepted)
            }
            throw error
        }
    }

    static func verify(manifest: NodusModelManifest, in directory: URL) throws {
        guard manifest.schemaVersion == 1, manifest.license == "Apache-2.0", manifest.quantization == "4-bit" else {
            throw NodusArtifactError.unsupportedManifest
        }
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: []
        ) else { throw NodusArtifactError.invalidManifest }
        var actualFiles = Set<String>()
        let directoryPath = directory.standardizedFileURL.path
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: resourceKeys)
            let filePath = file.standardizedFileURL.path
            guard filePath.hasPrefix(directoryPath + "/") else { throw NodusArtifactError.invalidManifest }
            let relativePath = String(filePath.dropFirst(directoryPath.count + 1))
            if values.isSymbolicLink == true { throw NodusArtifactError.symbolicLink(relativePath) }
            if values.isRegularFile == true, relativePath != "nodus-manifest.json" {
                actualFiles.insert(relativePath)
            }
        }
        let expectedFiles = Set(manifest.files.keys)
        guard actualFiles == expectedFiles else {
            let unexpected = actualFiles.subtracting(expectedFiles).sorted().first
                ?? expectedFiles.subtracting(actualFiles).sorted().first
                ?? "unknown"
            throw NodusArtifactError.unexpectedFile(unexpected)
        }
        for (relativePath, expected) in manifest.files {
            guard !relativePath.contains(".."), !relativePath.hasPrefix("/") else { throw NodusArtifactError.invalidManifest }
            let file = directory.appending(path: relativePath)
            guard FileManager.default.fileExists(atPath: file.path) else { throw NodusArtifactError.missingFile(relativePath) }
            guard try sha256(file) == expected else { throw NodusArtifactError.hashMismatch(relativePath) }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let encodedManifest = try encoder.encode(manifest)
        guard var canonicalManifest = try JSONSerialization.jsonObject(with: encodedManifest) as? [String: Any] else {
            throw NodusArtifactError.invalidManifest
        }
        canonicalManifest.removeValue(forKey: "artifactHash")
        let canonicalData = try JSONSerialization.data(
            withJSONObject: canonicalManifest,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let computedArtifactHash = "sha256:" + sha256(canonicalData)
        guard manifest.artifactHash == computedArtifactHash else {
            throw NodusArtifactError.artifactHashMismatch
        }
    }

    private static func decodeManifest(at url: URL) throws -> NodusModelManifest {
        do { return try JSONDecoder().decode(NodusModelManifest.self, from: Data(contentsOf: url)) }
        catch { throw NodusArtifactError.invalidManifest }
    }

    private static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { digest.update(data: data) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
