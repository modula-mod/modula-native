import CryptoKit
import Foundation
import os

private let trustLog = Logger(subsystem: "digital.modula.native", category: "ModuleTrust")

struct ModuleSignedFacts: Equatable, Sendable {
    var algorithm: String
    var signature: String
    var keyId: String
    var digest: String
    var digestAlgorithm: String

    init?(data: Data) {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data),
              let algorithm = json["algorithm"]?.string,
              let signature = json["signature"]?.string,
              let keyId = json["keyId"]?.string,
              let digest = json["digest"]?.string,
              let digestAlgorithm = json["digestAlgorithm"]?.string else { return nil }
        self.algorithm = algorithm
        self.signature = signature
        self.keyId = keyId
        self.digest = digest
        self.digestAlgorithm = digestAlgorithm
    }
}

struct TrustedSigner: Equatable, Sendable {
    var keyId: String
    var rawPublicKey: Data

    /// Ed25519 SPKI, the same bytes Node hashes for `keyId`.
    static let spkiPrefix = Data([0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00])

    static func keyId(for rawPublicKey: Data) -> String {
        SHA256.hash(data: spkiPrefix + rawPublicKey).map { String(format: "%02x", $0) }.joined()
    }

    static func load(from url: URL) -> TrustedSigner? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(pemOrBase64: text)
    }

    static func parse(pemOrBase64: String) -> TrustedSigner? {
        let body = pemOrBase64
            .split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let der = Data(base64Encoded: body.filter { !$0.isWhitespace }) else { return nil }
        let raw: Data
        if der.count == 32 {
            raw = der
        } else if der.count == spkiPrefix.count + 32, der.prefix(spkiPrefix.count) == spkiPrefix {
            raw = der.suffix(32)
        } else {
            return nil
        }
        return TrustedSigner(keyId: keyId(for: raw), rawPublicKey: raw)
    }
}

struct ModuleTrustPolicy: Equatable, Sendable {
    var signers: [TrustedSigner]
    var revokedKeyIds: Set<String>
    /// Local packages with no signed facts. Production keeps this false.
    var allowsUnsignedLocalPackages: Bool

    static func production() -> ModuleTrustPolicy {
        ModuleTrustPolicy(signers: [], revokedKeyIds: [], allowsUnsignedLocalPackages: false)
    }

    static var current: ModuleTrustPolicy {
        #if DEBUG
        development()
        #else
        production()
        #endif
    }

    #if DEBUG
    static func development(
        launchArguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ModuleTrustPolicy {
        var urls: [URL] = []
        if let index = launchArguments.firstIndex(of: "--modula-dev-trust-public-key"),
           launchArguments.indices.contains(launchArguments.index(after: index)) {
            urls.append(URL(fileURLWithPath: launchArguments[launchArguments.index(after: index)]))
        }
        if let path = environment["MODULA_DEV_TRUST_PUBLIC_KEY"], !path.isEmpty {
            urls.append(URL(fileURLWithPath: path))
        }
        let directory = URL(fileURLWithPath: "/Users/msjoy/.config/modula-dev", isDirectory: true)
        if let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            urls.append(contentsOf: entries.filter { $0.pathExtension == "pem" && $0.lastPathComponent.contains("pub") })
        }
        // A physical iPhone cannot read the Mac config directory. Debug builds also trust
        // public keys placed in this app's sandbox. The private key never ships in the app.
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let deviceTrust = support.appendingPathComponent("Modula/DevTrust", isDirectory: true)
            if let entries = try? FileManager.default.contentsOfDirectory(at: deviceTrust, includingPropertiesForKeys: nil) {
                urls.append(contentsOf: entries.filter { $0.pathExtension == "pem" && $0.lastPathComponent.contains("pub") })
            }
        }
        var signers: [TrustedSigner] = []
        var seen = Set<String>()
        for url in urls {
            guard let signer = TrustedSigner.load(from: url), seen.insert(signer.keyId).inserted else { continue }
            signers.append(signer)
        }
        var revoked = Set<String>()
        let revokedURL = directory.appendingPathComponent("revoked-key-ids.txt")
        if let text = try? String(contentsOf: revokedURL, encoding: .utf8) {
            for line in text.split(whereSeparator: \.isNewline) {
                let id = line.trimmingCharacters(in: .whitespaces)
                if id.count == 64 { revoked.insert(id) }
            }
        }
        return ModuleTrustPolicy(signers: signers, revokedKeyIds: revoked, allowsUnsignedLocalPackages: true)
    }
    #endif
}

enum ModuleTrustError: Error, Equatable, LocalizedError {
    case unsigned
    case untrustedSigner
    case revokedSigner
    case badSignature
    case digestMismatch
    case unsupportedAlgorithm

    var errorDescription: String? {
        switch self {
        case .unsigned: "This release is unsigned."
        case .untrustedSigner: "This release is signed by a key this app does not trust."
        case .revokedSigner: "This release is signed by a revoked key."
        case .badSignature: "The release signature does not match the trusted key."
        case .digestMismatch: "The signed digest does not match the package digest."
        case .unsupportedAlgorithm: "This release uses an unsupported signature algorithm."
        }
    }
}

enum ModuleReleaseTrust {
    /// Verifies an Ed25519 signature over the UTF-8 package digest, matching `modula sign`.
    /// `packagedDigest` is the on-disk `package.sha256` when that file exists.
    /// `artifact` is hashed only when the package bytes themselves are present.
    static func verify(facts: ModuleSignedFacts, packagedDigest: String?, artifact: Data?, policy: ModuleTrustPolicy) throws {
        guard facts.algorithm == "ed25519", facts.digestAlgorithm == "sha256" else {
            throw ModuleTrustError.unsupportedAlgorithm
        }
        guard facts.digest.count == 64, facts.digest.allSatisfy(\.isHexDigit) else {
            throw ModuleTrustError.digestMismatch
        }
        if let packagedDigest, packagedDigest.trimmingCharacters(in: .whitespacesAndNewlines) != facts.digest {
            throw ModuleTrustError.digestMismatch
        }
        if let artifact {
            let actual = SHA256.hash(data: artifact).map { String(format: "%02x", $0) }.joined()
            guard actual == facts.digest else { throw ModuleTrustError.digestMismatch }
        }
        if policy.revokedKeyIds.contains(facts.keyId) {
            trustLog.error("Revoked signer \(facts.keyId, privacy: .public)")
            throw ModuleTrustError.revokedSigner
        }
        guard let signer = policy.signers.first(where: { $0.keyId == facts.keyId }) else {
            trustLog.error("Untrusted signer \(facts.keyId, privacy: .public)")
            throw ModuleTrustError.untrustedSigner
        }
        guard TrustedSigner.keyId(for: signer.rawPublicKey) == facts.keyId,
              let signature = Data(base64Encoded: facts.signature),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: signer.rawPublicKey),
              key.isValidSignature(signature, for: Data(facts.digest.utf8)) else {
            trustLog.error("Bad signature for \(facts.keyId, privacy: .public)")
            throw ModuleTrustError.badSignature
        }
        trustLog.info("Verified release digest \(String(facts.digest.prefix(12)), privacy: .public)")
    }
}
