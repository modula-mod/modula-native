import CryptoKit
import Foundation
import zlib

/// One reviewed dispatch table for every signed/data-only package surface the
/// native host understands. Category and schema are part of the dispatch key:
/// a familiar media type in the wrong package shape remains unsupported.
enum PackageMediaCompatibility {
    enum PayloadKind: String, CaseIterable, Hashable, Sendable {
        case molibooContent, stickerManifest, stickerAsset
        case moduleContent, gubicGame, gubicRuntime
    }

    struct Rule: Equatable, Sendable {
        let kind: PayloadKind
        let schemaVersion: String
        let category: String
        let mediaType: String
    }

    static let packageSchemaVersion = "modula.package.1"
    static let stickerSchemaVersion = "modula.sticker-pack.1"
    static let moliboo = Rule(
        kind: .molibooContent, schemaVersion: packageSchemaVersion, category: "asset-pack",
        mediaType: "application/vnd.modula.moliboo-asset-pack+json"
    )
    static let stickerManifest = Rule(
        kind: .stickerManifest, schemaVersion: stickerSchemaVersion, category: "sticker-manifest",
        mediaType: "application/json"
    )
    static let stickerAsset = Rule(
        kind: .stickerAsset, schemaVersion: stickerSchemaVersion, category: "sticker-asset",
        mediaType: "image/png"
    )
    static let module = Rule(
        kind: .moduleContent, schemaVersion: packageSchemaVersion, category: "module",
        mediaType: "application/gzip"
    )
    static let gubicGame = Rule(
        kind: .gubicGame, schemaVersion: packageSchemaVersion, category: "game-content",
        mediaType: "application/vnd.modula.game-web+tgz"
    )
    static let gubicRuntime = Rule(
        kind: .gubicRuntime, schemaVersion: packageSchemaVersion, category: "web-runtime",
        mediaType: "application/vnd.modula.web-runtime+tgz"
    )

    static let rules = [moliboo, stickerManifest, stickerAsset, module, gubicGame, gubicRuntime]
    static let legacyGubicArchiveMediaType = "application/gzip"
    static let gubicInstalledArtifactMediaTypes = Set([legacyGubicArchiveMediaType, gubicGame.mediaType])
    /// Migration 077 introduced these generic blob types. Native does not execute
    /// the generic asset archive, but later migrations must preserve its storage.
    static let preMolibooOptionalDatabaseMediaTypes = Set([
        gubicGame.mediaType, gubicRuntime.mediaType, "application/vnd.modula.asset-pack+tgz"
    ])

    static func dispatch(schemaVersion: String, category: String, mediaType: String) -> PayloadKind? {
        rules.first {
            $0.schemaVersion == schemaVersion && $0.category == category && $0.mediaType == mediaType
        }?.kind
    }
}

enum WebGamePackageError: Error, LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        if case .invalid(let reason) = self { return "Downloaded package rejected: \(reason)" }
        return nil
    }
}

/// Parses the signed, content-addressed web archive before any file reaches WebKit.
/// This deliberately accepts only regular ustar files; links, PAX extensions,
/// devices, nested archives, and native binaries are not game content.
struct WebGamePackage {
    static let mediaType = PackageMediaCompatibility.gubicGame.mediaType
    static let maximumCompressedBytes = 50 * 1_024 * 1_024
    static let maximumExpandedBytes = 64 * 1_024 * 1_024
    let sha256: String
    let archive: Data
    let files: [String: Data]

    init(archive: Data, expectedSha256: String) throws {
        var files = try Self.members(archive: archive, expectedSha256: expectedSha256)
        guard let inventoryData = files.removeValue(forKey: "game.files.json"),
              let inventory = try? JSONDecoder().decode(Inventory.self, from: inventoryData),
              inventory.schema == "modula.game-files.1",
              Set(inventory.files.keys) == Set(files.keys),
              files["index.html"] != nil else {
            throw WebGamePackageError.invalid("inventory or entry document")
        }
        for (path, bytes) in files where inventory.files[path] != Self.digest(bytes) {
            throw WebGamePackageError.invalid("member digest: \(path)")
        }
        guard !files.keys.contains(where: { $0 == "__runtime" || $0.hasPrefix("__runtime/") }) else {
            throw WebGamePackageError.invalid("reserved shared runtime path")
        }
        guard let html = files["index.html"].flatMap({ String(data: $0, encoding: .utf8) }),
              html.localizedCaseInsensitiveContains("Content-Security-Policy"),
              html.contains("default-src 'none'"), html.contains("script-src 'self'"),
              html.contains("connect-src 'none'"), html.contains("object-src 'none'") else {
            throw WebGamePackageError.invalid("restrictive Content Security Policy")
        }
        self.sha256 = expectedSha256
        self.archive = archive
        self.files = files
    }

    static func members(archive: Data, expectedSha256: String) throws -> [String: Data] {
        guard archive.count <= Self.maximumCompressedBytes,
              Self.digest(archive) == expectedSha256 else {
            throw WebGamePackageError.invalid("archive size or SHA-256")
        }
        let tar = try Self.inflate(archive)
        var files = [String: Data]()
        var foldedPaths = Set<String>()
        var offset = 0
        var foundEnd = false
        while offset + 512 <= tar.count {
            let header = Array(tar[offset..<(offset + 512)])
            if header.allSatisfy({ $0 == 0 }) { foundEnd = true; break }
            guard files.count < 512 else { throw WebGamePackageError.invalid("too many members") }
            guard Array(header[257..<263]) == [117, 115, 116, 97, 114, 0] else {
                throw WebGamePackageError.invalid("unsupported tar format")
            }
            let checksum = try Self.octal(header[148..<156])
            var actualChecksum = 0
            for index in header.indices { actualChecksum += (148..<156).contains(index) ? 32 : Int(header[index]) }
            guard checksum == actualChecksum else { throw WebGamePackageError.invalid("tar checksum") }
            let path = try Self.ascii(header[0..<100])
            guard Self.safe(path), files[path] == nil else { throw WebGamePackageError.invalid("unsafe or duplicate path") }
            guard foldedPaths.insert(path.lowercased()).inserted else {
                throw WebGamePackageError.invalid("case-conflicting path")
            }
            let kind = header[156]
            guard kind == 0 || kind == 48 else { throw WebGamePackageError.invalid("non-regular member") }
            guard !Self.nativePayload(path) else { throw WebGamePackageError.invalid("native payload") }
            let size = try Self.octal(header[124..<136])
            guard size <= 30 * 1_024 * 1_024, size <= tar.count - offset - 512 else {
                throw WebGamePackageError.invalid("truncated or oversized member")
            }
            let content = Data(tar[(offset + 512)..<(offset + 512 + size)])
            guard !Self.nativeMagic(content) else { throw WebGamePackageError.invalid("native executable bytes") }
            files[path] = content
            offset += 512 + ((size + 511) / 512) * 512
        }
        guard foundEnd, tar[offset...].allSatisfy({ $0 == 0 }) else {
            throw WebGamePackageError.invalid("archive trailer")
        }
        return files
    }

    /// Recheck every byte on launch, including after a force quit. The custom
    /// scheme serves only files from this digest-named directory; WKWebView
    /// receives no local-file read grant.
    func install(in parent: URL) throws -> URL {
        let destination = parent.appendingPathComponent(sha256, isDirectory: true)
        let partial = parent.appendingPathComponent("\(sha256).partial", isDirectory: true)
        let manager = FileManager.default
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        if manager.fileExists(atPath: partial.path) { try manager.removeItem(at: partial) }
        try manager.createDirectory(at: partial, withIntermediateDirectories: true)
        do {
            for (path, bytes) in files {
                let target = partial.appendingPathComponent(path)
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: target, options: .atomic)
            }
            let inventory = Inventory(schema: "modula.game-files.1", files: files.mapValues(Self.digest))
            try JSONEncoder().encode(inventory).write(to: partial.appendingPathComponent("game.files.json"), options: .atomic)
            if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
            try manager.moveItem(at: partial, to: destination)
            return destination
        } catch {
            try? manager.removeItem(at: partial)
            throw error
        }
    }

    static func verifyInstalled(at directory: URL, expectedSha256: String, trustedFiles: [String: Data]) throws -> URL {
        let rootValues = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard directory.lastPathComponent == expectedSha256,
              rootValues.isSymbolicLink != true, rootValues.isDirectory == true,
              let data = try? Data(contentsOf: directory.appendingPathComponent("game.files.json")),
              let inventory = try? JSONDecoder().decode(Inventory.self, from: data),
              inventory.schema == "modula.game-files.1", inventory.files["index.html"] != nil,
              inventory.files == trustedFiles.mapValues(Self.digest) else {
            throw WebGamePackageError.invalid("installed inventory")
        }
        let manager = FileManager.default
        let members = try manager.subpathsOfDirectory(atPath: directory.path)
        var actual: [String] = []
        for path in members {
            guard safe(path) else { throw WebGamePackageError.invalid("installed path") }
            let values = try directory.appendingPathComponent(path).resourceValues(
                forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey]
            )
            guard values.isSymbolicLink != true else { throw WebGamePackageError.invalid("installed link") }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else { throw WebGamePackageError.invalid("installed member type") }
            actual.append(path)
        }
        guard Set(actual) == Set(inventory.files.keys).union(["game.files.json"]),
              Set(actual.map { $0.lowercased() }).count == actual.count else {
            throw WebGamePackageError.invalid("installed member set")
        }
        for (path, digest) in inventory.files {
            guard safe(path), !nativePayload(path) else { throw WebGamePackageError.invalid("installed path") }
            let url = directory.appendingPathComponent(path)
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            guard values.isSymbolicLink != true, values.isRegularFile == true,
                  let bytes = try? Data(contentsOf: url), Self.digest(bytes) == digest else {
                throw WebGamePackageError.invalid("installed digest: \(path)")
            }
        }
        return directory.appendingPathComponent("index.html")
    }

    struct Inventory: Codable { let schema: String; let files: [String: String] }
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    fileprivate static func safe(_ path: String) -> Bool {
        path.count > 0 && path.count <= 100 && !path.hasPrefix("/") && !path.contains("\\") &&
        path.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) ||
            (97...122).contains($0) || $0 == 45 || $0 == 46 || $0 == 95 || $0 == 47 } &&
        !path.split(separator: "/", omittingEmptySubsequences: false).contains { $0 == "." || $0 == ".." || $0.isEmpty }
    }
    fileprivate static func nativePayload(_ path: String) -> Bool {
        let lower = path.lowercased()
        return [".app", ".framework", ".dylib", ".so", ".dll", ".exe", ".node", ".ipa", ".a", ".o", ".wasm", ".jar", ".class", ".cs"].contains { lower.hasSuffix($0) || lower.contains("\($0)/") }
    }
    private static func nativeMagic(_ bytes: Data) -> Bool {
        let head = Array(bytes.prefix(4))
        return head == [0x7f, 0x45, 0x4c, 0x46] || head.prefix(2) == [0x4d, 0x5a] ||
            [[0xfe, 0xed, 0xfa, 0xce], [0xce, 0xfa, 0xed, 0xfe], [0xfe, 0xed, 0xfa, 0xcf],
             [0xcf, 0xfa, 0xed, 0xfe], [0xca, 0xfe, 0xba, 0xbe], [0xbe, 0xba, 0xfe, 0xca]].contains(head)
    }
    private static func ascii(_ bytes: ArraySlice<UInt8>) throws -> String {
        let text = bytes.prefix { $0 != 0 }
        guard text.allSatisfy({ $0 < 128 }), let string = String(bytes: text, encoding: .ascii) else {
            throw WebGamePackageError.invalid("tar path encoding")
        }
        return string
    }
    private static func octal(_ bytes: ArraySlice<UInt8>) throws -> Int {
        let value = try ascii(bytes).trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, value.utf8.allSatisfy({ (48...55).contains($0) }),
              let number = Int(value, radix: 8) else { throw WebGamePackageError.invalid("tar number") }
        return number
    }
    private static func inflate(_ archive: Data) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw WebGamePackageError.invalid("gzip initialization")
        }
        defer { inflateEnd(&stream) }
        var input = [UInt8](archive)
        let inputCount = input.count
        var output = Data()
        let status: Int32 = input.withUnsafeMutableBytes { inputBytes in
            stream.next_in = inputBytes.baseAddress?.assumingMemoryBound(to: Bytef.self)
            stream.avail_in = uInt(inputCount)
            while true {
                var chunk = [UInt8](repeating: 0, count: 64 * 1_024)
                let chunkCount = chunk.count
                let code: Int32 = chunk.withUnsafeMutableBytes { outBytes in
                    stream.next_out = outBytes.baseAddress?.assumingMemoryBound(to: Bytef.self)
                    stream.avail_out = uInt(chunkCount)
                    return zlib.inflate(&stream, Z_NO_FLUSH)
                }
                output.append(contentsOf: chunk.prefix(chunkCount - Int(stream.avail_out)))
                if output.count > maximumExpandedBytes { return Z_MEM_ERROR }
                if code == Z_STREAM_END { return code }
                if code != Z_OK || stream.avail_in == 0 { return code == Z_OK ? Z_DATA_ERROR : code }
            }
        }
        guard status == Z_STREAM_END else { throw WebGamePackageError.invalid("gzip data or expansion limit") }
        return output
    }
}

/// A signed web-runtime archive has one engine module and no HTML entry point.
/// It is parsed with the same strict ustar and native-payload checks as game content.
struct WebRuntimePackage {
    static let mediaType = PackageMediaCompatibility.gubicRuntime.mediaType
    let sha256: String
    let archive: Data
    let engine: Data

    init(archive: Data, expectedSha256: String) throws {
        var files = try WebGamePackage.members(archive: archive, expectedSha256: expectedSha256)
        guard let inventoryData = files.removeValue(forKey: "package.files.json"),
              let inventory = try? JSONDecoder().decode(WebGamePackage.Inventory.self, from: inventoryData),
              inventory.schema == "modula.package-files.1",
              Set(files.keys) == Set(["engine.mjs"]),
              inventory.files == ["engine.mjs": WebGamePackage.digest(files["engine.mjs"]!)],
              let engine = files["engine.mjs"],
              String(data: engine, encoding: .utf8) != nil else {
            throw WebGamePackageError.invalid("web runtime inventory")
        }
        self.sha256 = expectedSha256
        self.archive = archive
        self.engine = engine
    }
}

/// A content-only module package uses the same fail-closed archive rules as a
/// web game but never exposes downloaded bytes as executable code. Its Product
/// UI document is the only entry the existing declarative ModuleHost consumes.
struct ModuleContentPackage {
    static let mediaType = PackageMediaCompatibility.module.mediaType
    static let frontendPath = "frontend/frontend.manifest.json"

    let sha256: String
    let archive: Data
    let files: [String: Data]
    let frontend: Data

    init(archive: Data, expectedSha256: String) throws {
        var members = try WebGamePackage.members(archive: archive, expectedSha256: expectedSha256)
        guard let inventoryData = members.removeValue(forKey: "package.files.json"),
              let inventory = try? JSONDecoder().decode(WebGamePackage.Inventory.self, from: inventoryData),
              inventory.schema == "modula.package-files.1",
              Set(inventory.files.keys) == Set(members.keys),
              let frontend = members[Self.frontendPath] else {
            throw WebGamePackageError.invalid("module inventory or frontend")
        }
        for (path, bytes) in members where inventory.files[path] != WebGamePackage.digest(bytes) {
            throw WebGamePackageError.invalid("module member digest: \(path)")
        }
        self.sha256 = expectedSha256
        self.archive = archive
        files = members
        self.frontend = frontend
    }

    func install(in parent: URL) throws -> URL {
        let destination = parent.appendingPathComponent(sha256, isDirectory: true)
        let partial = parent.appendingPathComponent("\(sha256).partial", isDirectory: true)
        let manager = FileManager.default
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        if manager.fileExists(atPath: partial.path) { try manager.removeItem(at: partial) }
        try manager.createDirectory(at: partial, withIntermediateDirectories: true)
        do {
            for (path, bytes) in files {
                let target = partial.appendingPathComponent(path)
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: target, options: .atomic)
            }
            let inventory = WebGamePackage.Inventory(
                schema: "modula.package-files.1", files: files.mapValues(WebGamePackage.digest)
            )
            try JSONEncoder().encode(inventory).write(
                to: partial.appendingPathComponent("package.files.json"), options: .atomic
            )
            if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
            try manager.moveItem(at: partial, to: destination)
            return destination
        } catch {
            try? manager.removeItem(at: partial)
            throw error
        }
    }

    /// Revalidates both the immutable archive and every extracted member on
    /// each launch. Extra files, links, replacements, and partial installs fail.
    static func verifyInstalled(
        at directory: URL,
        archiveURL: URL,
        expectedSha256: String
    ) throws -> Data {
        let archiveValues = try archiveURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard archiveValues.isRegularFile == true, archiveValues.isSymbolicLink != true else {
            throw WebGamePackageError.invalid("module archive type")
        }
        let trusted = try ModuleContentPackage(
            archive: Data(contentsOf: archiveURL), expectedSha256: expectedSha256
        )
        let rootValues = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard directory.lastPathComponent == expectedSha256,
              rootValues.isDirectory == true, rootValues.isSymbolicLink != true,
              let inventoryData = try? Data(contentsOf: directory.appendingPathComponent("package.files.json")),
              let inventory = try? JSONDecoder().decode(WebGamePackage.Inventory.self, from: inventoryData),
              inventory.schema == "modula.package-files.1",
              inventory.files == trusted.files.mapValues(WebGamePackage.digest) else {
            throw WebGamePackageError.invalid("installed module inventory")
        }
        let manager = FileManager.default
        let members = try manager.subpathsOfDirectory(atPath: directory.path)
        var actual: [String] = []
        for path in members {
            guard WebGamePackage.safe(path) else { throw WebGamePackageError.invalid("installed module path") }
            let values = try directory.appendingPathComponent(path).resourceValues(
                forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey]
            )
            guard values.isSymbolicLink != true else { throw WebGamePackageError.invalid("installed module link") }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true else { throw WebGamePackageError.invalid("installed module member type") }
            actual.append(path)
        }
        guard Set(actual) == Set(inventory.files.keys).union(["package.files.json"]),
              Set(actual.map { $0.lowercased() }).count == actual.count else {
            throw WebGamePackageError.invalid("installed module member set")
        }
        for (path, digest) in inventory.files {
            guard WebGamePackage.safe(path), !WebGamePackage.nativePayload(path) else {
                throw WebGamePackageError.invalid("installed module path")
            }
            let url = directory.appendingPathComponent(path)
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  let bytes = try? Data(contentsOf: url), WebGamePackage.digest(bytes) == digest else {
                throw WebGamePackageError.invalid("installed module digest: \(path)")
            }
        }
        return trusted.frontend
    }
}
