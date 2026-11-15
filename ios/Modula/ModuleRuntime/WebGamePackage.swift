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
        guard let html = files["index.html"].flatMap({ String(data: $0, encoding: .utf8) }) else {
            throw WebGamePackageError.invalid("restrictive Content Security Policy")
        }
        // Hygiene only: the security boundary is the host's own header CSP and
        // local-only rule list (WebGameHost), never a document-declared policy.
        if !WebGamePackage.skipsDocumentPolicyHygiene {
            do {
                _ = try WebGameDocumentPolicy.validate(html: html)
            } catch WebGameDocumentPolicy.Rejection.policy(let reason) {
                throw WebGamePackageError.invalid("restrictive Content Security Policy: \(reason)")
            }
        }
        self.sha256 = expectedSha256
        self.archive = archive
        self.files = files
    }

    #if DEBUG
    /// Tests only: lets a hostile document that a validator missed reach the
    /// production host, to prove the host header CSP and rule list contain it.
    @TaskLocal static var skipsDocumentPolicyHygiene = false
    #else
    static var skipsDocumentPolicyHygiene: Bool { false }
    #endif

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

/// Parses the entry document's declared Content-Security-Policy instead of
/// matching substrings, mirroring the intent of GreenField's ingestion gate
/// (services/greenfield-api/src/gubic/web-game-csp.ts, #182). It refuses
/// anything it cannot interpret unambiguously.
///
/// This is package hygiene, NOT a security boundary: HTML parsing here can
/// never be guaranteed to match WebKit's (GreenField #188 had 8 bypasses).
/// The boundary is the host header CSP on every response plus the fail-closed
/// local-only WKContentRuleList in WebGameHost, which no document can relax.
enum WebGameDocumentPolicy {
    enum Rejection: Error, Equatable { case policy(String) }
    typealias Directives = [String: [String]]

    /// Directives a game document may declare. Anything else is refused.
    static let allowedDirectives: Set<String> = [
        "default-src", "script-src", "script-src-elem", "script-src-attr", "style-src", "style-src-elem",
        "style-src-attr", "img-src", "font-src", "media-src", "connect-src", "object-src", "worker-src",
        "child-src", "frame-src", "manifest-src", "base-uri", "form-action",
    ]
    /// Directives that govern executable code: only 'self' or 'none'.
    static let codeDirectives: Set<String> = [
        "script-src", "script-src-elem", "script-src-attr", "worker-src", "child-src", "frame-src", "object-src",
    ]
    /// Inline styles are inert without script; the host header still governs them.
    static let inlineStyleDirectives: Set<String> = ["style-src", "style-src-elem", "style-src-attr"]
    private static let rawTextElements = ["script", "style", "title", "textarea", "xmp", "iframe",
                                          "noembed", "noframes", "noscript", "template"]
    private static let tagPattern = #"(?:[^>"']|"[^"]*"|'[^']*')*>"#

    /// Extracts exactly one effective CSP meta element from the document head,
    /// then parses and validates its directives.
    @discardableResult
    static func validate(html: String) throws -> Directives {
        // `<!-->` and `<!--->` are complete (abruptly closed) comments in HTML;
        // `--!>` also closes one. Treating them otherwise hides markup.
        let uncommented = replace(#"<!--(?:>|->|[\s\S]*?(?:--!?>|$))"#, in: html, with: " ")
        var markup = uncommented
        for name in rawTextElements {
            markup = replace("(<\(name)\\b[^>]*>)[\\s\\S]*?(?:</\(name)\\s*>|$)", in: markup, with: "$1</\(name)>")
        }
        let text = markup as NSString
        var metas: [NSRange] = []
        for range in matches("<meta\\b" + tagPattern, in: markup) {
            guard let equiv = try attributes(of: text.substring(with: range))["http-equiv"]?.lowercased() else { continue }
            if equiv == "content-security-policy" {
                metas.append(range)
            } else if equiv.trimmingCharacters(in: .whitespacesAndNewlines) == "content-security-policy" {
                // Browsers may or may not honour a padded name; refuse the ambiguity.
                throw Rejection.policy("ambiguous http-equiv \"\(equiv)\"")
            }
        }
        guard metas.count == 1, let meta = metas.first else {
            throw Rejection.policy(metas.isEmpty ? "no effective CSP meta element" : "more than one CSP meta element")
        }
        let prefix = text.substring(to: meta.location).replacingOccurrences(of: "\u{FEFF}", with: "")
        let allowedBefore = "<!doctype\\b[^>]*>|<html\\b[^>]*>|<head\\b[^>]*>|<title\\b[^>]*></title>|<meta\\b" + tagPattern
        guard replace(allowedBefore, in: prefix, with: "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Rejection.policy("CSP must be declared in <head> before any other content")
        }
        guard let content = try attributes(of: text.substring(with: meta))["content"],
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Rejection.policy("empty CSP")
        }
        let directives = try parse(content)
        try assertRestrictive(directives)
        return directives
    }

    /// Splits a serialized policy into directive name and source list.
    /// Duplicate directives and multiple policies are refused, not ignored.
    static func parse(_ policy: String) throws -> Directives {
        guard !policy.contains(",") else { throw Rejection.policy("must be a single policy") }
        var directives = Directives()
        for raw in policy.split(separator: ";", omittingEmptySubsequences: false) {
            let tokens = raw.components(separatedBy: CharacterSet(charactersIn: " \t\n\r\u{0C}")).filter { !$0.isEmpty }
            guard let first = tokens.first else { continue }
            let name = first.lowercased()
            guard name.range(of: "^[a-z0-9-]+$", options: .regularExpression) != nil else { throw Rejection.policy("invalid directive name \(first)") }
            guard directives[name] == nil else { throw Rejection.policy("repeats the \(name) directive") }
            directives[name] = Array(tokens.dropFirst())
        }
        return directives
    }

    static func assertRestrictive(_ directives: Directives) throws {
        for (name, sources) in directives {
            guard allowedDirectives.contains(name) else { throw Rejection.policy("directive not permitted: \(name)") }
            guard !sources.isEmpty else { throw Rejection.policy("\(name) has no sources") }
            for source in sources {
                let lower = source.lowercased()
                if ["'unsafe-eval'", "'wasm-unsafe-eval'", "'unsafe-hashes'"].contains(lower) ||
                    (lower == "'unsafe-inline'" && !inlineStyleDirectives.contains(name)) {
                    throw Rejection.policy("must not allow \(lower) (\(name))")
                }
                if lower == "'none'" && sources.count > 1 { throw Rejection.policy("\(name) mixes 'none' with other sources") }
                if lower.contains("*") { throw Rejection.policy("wildcard source (\(name))") }
                if codeDirectives.contains(name) {
                    guard lower == "'self'" || lower == "'none'" else {
                        throw Rejection.policy("\(name) may only allow 'self' (found \(source))")
                    }
                    continue
                }
                if ["'self'", "'none'", "data:", "blob:", "'unsafe-inline'"].contains(lower) { continue }
                throw Rejection.policy("remote or non-local source (\(name): \(source))")
            }
        }
        for name in ["default-src", "connect-src", "object-src"] {
            guard directives[name]?.map({ $0.lowercased() }) == ["'none'"] else {
                throw Rejection.policy("must set \(name) 'none'")
            }
        }
        guard directives["script-src"]?.map({ $0.lowercased() }) == ["'self'"] else {
            throw Rejection.policy("must set script-src 'self'")
        }
    }

    /// Attributes of one start tag; duplicates keep the first value, as in HTML.
    static func attributes(of tag: String) throws -> [String: String] {
        let body = replace(#"/?>$"#, in: replace(#"^<[A-Za-z0-9-]+"#, in: tag, with: ""), with: "")
        let text = body as NSString
        var result = [String: String]()
        let pattern = #"([^\s"'>/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        for match in regex.matches(in: body, range: NSRange(location: 0, length: text.length)) {
            let name = text.substring(with: match.range(at: 1)).lowercased()
            guard result[name] == nil else { continue }
            var value = ""
            for group in 2...4 where match.range(at: group).location != NSNotFound {
                value = text.substring(with: match.range(at: group))
                break
            }
            result[name] = try decodeEntities(value)
        }
        return result
    }

    private static func decodeEntities(_ value: String) throws -> String {
        let text = value as NSString
        guard let regex = try? NSRegularExpression(pattern: "&([A-Za-z0-9#]+);") else { return value }
        var output = ""
        var cursor = 0
        for match in regex.matches(in: value, range: NSRange(location: 0, length: text.length)) {
            output += text.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let name = text.substring(with: match.range(at: 1))
            let lower = name.lowercased()
            let scalar: UnicodeScalar?
            if lower.hasPrefix("#x") {
                scalar = UInt32(lower.dropFirst(2), radix: 16).flatMap { UnicodeScalar($0) }
            } else if lower.hasPrefix("#") {
                scalar = UInt32(lower.dropFirst(), radix: 10).flatMap { UnicodeScalar($0) }
            } else {
                scalar = ["quot": "\"", "apos": "'", "lt": "<", "gt": ">", "amp": "&"][lower].flatMap { $0.unicodeScalars.first }
            }
            guard let scalar else { throw Rejection.policy("unsupported character reference &\(name);") }
            output.unicodeScalars.append(scalar)
            cursor = match.range.location + match.range.length
        }
        output += text.substring(from: cursor)
        return output
    }

    private static func matches(_ pattern: String, in string: String) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: string, range: NSRange(location: 0, length: (string as NSString).length)).map(\.range)
    }

    private static func replace(_ pattern: String, in string: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return string }
        return regex.stringByReplacingMatches(in: string, range: NSRange(location: 0, length: (string as NSString).length),
                                              withTemplate: template)
    }
}

/// A signed web-runtime archive has one engine module and no HTML entry point.
/// It is parsed with the same strict ustar and native-payload checks as game content.
struct WebRuntimePackage {
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
