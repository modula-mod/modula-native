import CryptoKit
import Foundation
import zlib

enum WebGamePackageError: Error, LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        if case .invalid(let reason) = self { return "Game package rejected: \(reason)" }
        return nil
    }
}

/// Parses the signed, content-addressed web archive before any file reaches WebKit.
/// This deliberately accepts only regular ustar files; links, PAX extensions,
/// devices, nested archives, and native binaries are not game content.
struct WebGamePackage {
    static let mediaType = "application/vnd.modula.game-web+tgz"
    static let maximumCompressedBytes = 50 * 1_024 * 1_024
    static let maximumExpandedBytes = 64 * 1_024 * 1_024
    let sha256: String
    let archive: Data
    let files: [String: Data]

    init(archive: Data, expectedSha256: String) throws {
        guard archive.count <= Self.maximumCompressedBytes,
              Self.digest(archive) == expectedSha256 else {
            throw WebGamePackageError.invalid("archive size or SHA-256")
        }
        let tar = try Self.inflate(archive)
        var files = [String: Data]()
        var offset = 0
        var foundEnd = false
        while offset + 512 <= tar.count {
            let header = Array(tar[offset..<(offset + 512)])
            if header.allSatisfy({ $0 == 0 }) { foundEnd = true; break }
            guard files.count < 512 else { throw WebGamePackageError.invalid("too many members") }
            let checksum = try Self.octal(header[148..<156])
            var actualChecksum = 0
            for index in header.indices { actualChecksum += (148..<156).contains(index) ? 32 : Int(header[index]) }
            guard checksum == actualChecksum else { throw WebGamePackageError.invalid("tar checksum") }
            let path = try Self.ascii(header[0..<100])
            guard Self.safe(path), files[path] == nil else { throw WebGamePackageError.invalid("unsafe or duplicate path") }
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
        guard Set(actual) == Set(inventory.files.keys).union(["game.files.json"]) else {
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

    private struct Inventory: Codable { let schema: String; let files: [String: String] }
    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private static func safe(_ path: String) -> Bool {
        path.count > 0 && path.count <= 100 && !path.hasPrefix("/") && !path.contains("\\") &&
        path.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) ||
            (97...122).contains($0) || $0 == 45 || $0 == 46 || $0 == 95 || $0 == 47 } &&
        !path.split(separator: "/", omittingEmptySubsequences: false).contains { $0 == "." || $0 == ".." || $0.isEmpty }
    }
    private static func nativePayload(_ path: String) -> Bool {
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
