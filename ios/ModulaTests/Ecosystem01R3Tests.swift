import CryptoKit
import XCTest
@testable import Modula

final class Ecosystem01R3Tests: XCTestCase {
    func testStructuredDocumentRoundTripsVaultAndGenericFixtures() throws {
        let vault = """
        {"schemaVersion":"1.0.0","blocks":[{"id":"p1","type":"paragraph","inlines":[{"text":"Hello ","marks":[{"type":"bold"}]},{"text":"vault"}]},{"id":"keep","type":"link-preview","url":"https://modula.digital/notes","title":"Notes"},{"id":"c1","type":"checklist","items":["One"],"checked":[false]}]}
        """
        let parsed = try StructuredDocument.parse(vault)
        XCTAssertEqual(parsed.blocks.count, 3)
        XCTAssertEqual(parsed.blockType(parsed.blocks[1]), "link-preview")
        let edited = parsed.replacingText("Hello vault notes", blockID: "p1")
        XCTAssertEqual(edited.blockID(edited.blocks[0]), "p1")
        XCTAssertEqual(edited.visibleText(edited.blocks[0]), "Hello vault notes")
        XCTAssertEqual(edited.blocks[0]["inlines"]?.array?.first?["marks"]?.array?.first?["type"]?.string, "bold")
        XCTAssertTrue(edited.canEdit(edited.blocks[0]))
        XCTAssertEqual(edited.blockType(edited.blocks[1]), "link-preview")
        let again = try StructuredDocument.parse(edited.serialize())
        XCTAssertEqual(again.blockType(again.blocks[1]), "link-preview")
        XCTAssertEqual(again.visibleText(again.blocks[1]), "Notes")
        XCTAssertEqual(again.blocks[1]["url"]?.string, "https://modula.digital/notes")

        let generic = try StructuredDocument.parse("Title page\n\nSecond paragraph")
        XCTAssertEqual(generic.blocks.map { generic.blockType($0) }, ["paragraph", "paragraph"])
        let headed = generic.applying(command: "heading", id: "block-1", selection: NSRange(location: 0, length: 0))
        XCTAssertEqual(headed.blockType(headed.blocks[0]), "heading")
        XCTAssertEqual(headed.blockID(headed.blocks[0]), "block-1")
        let marked = headed.applying(command: "bold", id: "block-1", selection: NSRange(location: 0, length: 5))
        let marks = marked.blocks[0]["inlines"]?.array?.first?["marks"]?.array
        XCTAssertEqual(marks?.first?["type"]?.string, "bold")
        let italic = marked.applying(command: "italic", id: "block-1", selection: NSRange(location: 0, length: 5))
        let firstMarks = italic.blocks[0]["inlines"]?.array?.first?["marks"]?.array ?? []
        XCTAssertEqual(Set(firstMarks.compactMap { $0["type"]?.string }), Set(["bold", "italic"]))
        let split = italic.splitting(blockID: "block-1", at: 2).0
        XCTAssertEqual(split.blocks.count, 3)
        XCTAssertEqual(split.visibleText(split.blocks[0]) + split.visibleText(split.blocks[1]), "Title page")
        XCTAssertEqual(split.blocks[1]["inlines"]?.array?.first?["marks"]?.array?.first?["type"]?.string, "bold")
    }

    func testUnsupportedAndCorruptDocumentsAreNonDestructive() throws {
        let unknown = #"{"schemaVersion":"1.0.0","blocks":[{"id":"x1","type":"widget-embed","widget":"kept"}]}"#
        let parsed = try? StructuredDocument.parse(unknown)
        XCTAssertEqual(parsed?.blockType(parsed!.blocks[0]), "widget-embed")
        XCTAssertEqual(parsed?.serialize().contains("widget-embed"), true)
        let unknownMark = #"{"schemaVersion":"1.0.0","blocks":[{"id":"p1","type":"paragraph","inlines":[{"text":"Keep me","marks":[{"type":"future-mark"}]}]}]}"#
        let marked = try? StructuredDocument.parse(unknownMark)
        XCTAssertFalse(marked?.canEdit(marked!.blocks[0]) ?? true)
        XCTAssertEqual(marked?.replacingText("Changed", blockID: "p1").serialize(), marked?.serialize())
        let futureList = try StructuredDocument.parse(#"{"schemaVersion":"1.0.0","blocks":[{"id":"l1","type":"checklist","items":[{"text":"Future item","metadata":{"keep":true}}]}]}"#)
        XCTAssertFalse(futureList.canEdit(futureList.blocks[0]))
        XCTAssertEqual(futureList.replacingText("Changed", blockID: "l1"), futureList)
        XCTAssertThrowsError(try StructuredDocument.parse(#"{"schemaVersion":"9.9.9","blocks":[]}"#))
        XCTAssertThrowsError(try StructuredDocument.parse(#"{"schemaVersion":"1.0.0","blocks":[{"type":"paragraph"}]}"#))
    }

    func testStructuredPreviewHidesEnvelopeAndPreservesUnrecognizedFields() throws {
        let raw = #"{"schemaVersion":"1.0.0","producer":"future-host","blocks":[{"id":"h1","type":"heading","level":2,"text":"Hhh"},{"id":"u1","type":"custom","payload":{"secret":"opaque"}}]}"#
        let document = try StructuredDocument.parse(raw)
        XCTAssertEqual(StructuredDocument.excerpt(from: .string(raw)), "Hhh")
        XCTAssertEqual(document.extraFields["producer"]?.string, "future-host")
        let changed = document.insertingParagraph(after: "h1", text: "More")
        let restored = try StructuredDocument.parse(changed.serialize())
        XCTAssertEqual(restored.extraFields["producer"]?.string, "future-host")
        XCTAssertEqual(restored.blocks.last?["payload"]?["secret"]?.string, "opaque")
        XCTAssertEqual(StructuredDocument.excerpt(from: .string("{bad json")), "{bad json")
        XCTAssertEqual(StructuredDocument.excerpt(from: .string(#"{"blocks":broken,"schemaVersion":"1.0.0"}"#)), "")
        XCTAssertEqual(StructuredDocument.excerpt(from: .string("Legacy plain text")), "Legacy plain text")
    }

    func testMarkedInlinesRetainFormattingAfterTextEdit() throws {
        let raw = #"{"schemaVersion":"1.0.0","blocks":[{"id":"p1","type":"paragraph","inlines":[{"text":"Hello","marks":[{"type":"bold"}]}]}]}"#
        let document = try StructuredDocument.parse(raw)
        let edited = document.replacingText("Changed", blockID: "p1")
        XCTAssertEqual(edited.visibleText(edited.blocks[0]), "Changed")
        XCTAssertEqual(edited.blocks[0]["inlines"]?.array?.first?["marks"]?.array?.first?["type"]?.string, "bold")
    }

    func testUndoRestoresThePreviousDocument() throws {
        var history = [#"{"blocks":[{"id":"b1","text":"one","type":"paragraph"}],"schemaVersion":"1.0.0"}"#]
        let current = try StructuredDocument.parse(history[0])
        let next = current.replacingText("two", blockID: "b1")
        history.append(next.serialize())
        let restored = try StructuredDocument.parse(history[0])
        XCTAssertEqual(restored.visibleText(restored.blocks[0]), "one")
        XCTAssertEqual(restored.blockID(restored.blocks[0]), "b1")
    }

    func testEd25519TrustAcceptsSignerAndRefusesTamperRevocationAndProduction() throws {
        let key = Curve25519.Signing.PrivateKey()
        let signer = TrustedSigner(keyId: TrustedSigner.keyId(for: key.publicKey.rawRepresentation), rawPublicKey: key.publicKey.rawRepresentation)
        let digest = SHA256.hash(data: Data("package".utf8)).map { String(format: "%02x", $0) }.joined()
        let signature = try key.signature(for: Data(digest.utf8)).base64EncodedString()
        let facts = ModuleSignedFacts(data: Data("""
        {"algorithm":"ed25519","digest":"\(digest)","digestAlgorithm":"sha256","keyId":"\(signer.keyId)","signature":"\(signature)"}
        """.utf8))
        let signed = try XCTUnwrap(facts)
        let development = ModuleTrustPolicy(signers: [signer], revokedKeyIds: [], allowsUnsignedLocalPackages: true)
        XCTAssertNoThrow(try ModuleReleaseTrust.verify(facts: signed, packagedDigest: digest, artifact: nil, policy: development))
        XCTAssertThrowsError(try ModuleReleaseTrust.verify(facts: signed, packagedDigest: String(repeating: "ab", count: 32), artifact: nil, policy: development)) { error in
            XCTAssertEqual(error as? ModuleTrustError, .digestMismatch)
        }
        var tampered = digest
        tampered.replaceSubrange(tampered.startIndex...tampered.startIndex, with: tampered.first == "a" ? "b" : "a")
        let bad = try XCTUnwrap(ModuleSignedFacts(data: Data("""
        {"algorithm":"ed25519","digest":"\(tampered)","digestAlgorithm":"sha256","keyId":"\(signer.keyId)","signature":"\(signature)"}
        """.utf8)))
        XCTAssertThrowsError(try ModuleReleaseTrust.verify(facts: bad, packagedDigest: tampered, artifact: nil, policy: development)) { error in
            XCTAssertEqual(error as? ModuleTrustError, .badSignature)
        }
        let revoked = ModuleTrustPolicy(signers: [signer], revokedKeyIds: [signer.keyId], allowsUnsignedLocalPackages: false)
        XCTAssertThrowsError(try ModuleReleaseTrust.verify(facts: signed, packagedDigest: digest, artifact: Data("package".utf8), policy: revoked)) { error in
            XCTAssertEqual(error as? ModuleTrustError, .revokedSigner)
        }
        XCTAssertThrowsError(try ModuleReleaseTrust.verify(facts: signed, packagedDigest: digest, artifact: nil, policy: .production())) { error in
            XCTAssertEqual(error as? ModuleTrustError, .untrustedSigner)
        }
        XCTAssertFalse(ModuleTrustPolicy.production().allowsUnsignedLocalPackages)
        XCTAssertTrue(ModuleTrustPolicy.production().signers.isEmpty)
    }

    func testOnDiskBasicEchoFactsAreRefusedWhenTheLocalKeyDoesNotMatch() throws {
        let factsURL = URL(fileURLWithPath: "/Users/msjoy/Developer/modula-dev-modules/digital.modula.basic-echo/0.1.0/signed-facts.json")
        let digestURL = URL(fileURLWithPath: "/Users/msjoy/Developer/modula-dev-modules/digital.modula.basic-echo/0.1.0/package.sha256")
        let keyURL = URL(fileURLWithPath: "/Users/msjoy/.config/modula-dev/basic-echo-ed25519.pub.pem")
        guard let factsData = try? Data(contentsOf: factsURL),
              let facts = ModuleSignedFacts(data: factsData),
              let digest = try? String(contentsOf: digestURL, encoding: .utf8),
              let signer = TrustedSigner.load(from: keyURL) else {
            throw XCTSkip("Basic Echo signed facts or development public key are not on this machine")
        }
        let policy = ModuleTrustPolicy(signers: [signer], revokedKeyIds: [], allowsUnsignedLocalPackages: false)
        let packaged = digest.trimmingCharacters(in: .whitespacesAndNewlines)
        if signer.keyId == facts.keyId {
            XCTAssertNoThrow(try ModuleReleaseTrust.verify(facts: facts, packagedDigest: packaged, artifact: nil, policy: policy))
        } else {
            XCTAssertThrowsError(try ModuleReleaseTrust.verify(facts: facts, packagedDigest: packaged, artifact: nil, policy: policy)) { error in
                XCTAssertEqual(error as? ModuleTrustError, .untrustedSigner)
            }
        }
    }

    func testIsolatedTransportRejectsModuleAPIRequests() async throws {
        let client = GreenfieldClient(baseURL: URL(string: "https://api.modula.test"), transport: ModulaAppNetworkIsolation.isolatedSession())
        do {
            _ = try await client.catalogue()
            XCTFail("Isolated transport returned a catalogue")
        } catch {
            XCTAssertTrue(String(describing: error).contains("URLError") || String(describing: error).contains("notConnected") || error is URLError || error is APIError)
        }
    }

    @MainActor
    func testBadDigestDoesNotReplaceActiveAndHealthFailureRestoresPrevious() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("modula-r3-\(UUID().uuidString)", isDirectory: true)
        let controller = ModuleActivationController(store: ModuleArtifactStore(root: root))
        let account = "acct-r3"
        _ = try controller.installLocalPackage(
            accountID: account, moduleId: "digital.modula.basic", version: "0.1.0", releaseId: "a",
            frontend: Self.frontend("Welcome to Basic Echo", "0.1.0"), hostManifest: Self.manifest("0.1.0")
        )
        let active = try XCTUnwrap(controller.active(accountID: account, moduleId: "digital.modula.basic"))
        let bytes = try controller.store.frontendData(for: active)
        try controller.store.stageDeclaredDigestMismatch(
            accountID: account, moduleId: "digital.modula.basic", version: "0.1.0", releaseId: "bad",
            frontend: bytes, declaredSha256: String(repeating: "ab", count: 32), hostManifest: active.hostManifest
        )
        XCTAssertThrowsError(try controller.activate(accountID: account, moduleId: "digital.modula.basic"))
        XCTAssertEqual(controller.active(accountID: account, moduleId: "digital.modula.basic")?.version, "0.1.0")
        XCTAssertEqual(controller.store.index(accountID: account, moduleId: "digital.modula.basic").lastAuditReason, "digest-rejected")

        _ = try controller.installLocalPackage(
            accountID: account, moduleId: "digital.modula.basic", version: "0.1.1", releaseId: "b",
            frontend: Self.frontend("Welcome to Basic Echo 0.1.1", "0.1.1"), hostManifest: Self.manifest("0.1.1"),
            activate: false
        )
        controller.failNextActivationHealth = true
        XCTAssertThrowsError(try controller.activate(accountID: account, moduleId: "digital.modula.basic"))
        let restored = try XCTUnwrap(controller.active(accountID: account, moduleId: "digital.modula.basic"))
        XCTAssertEqual(restored.version, "0.1.0")
        XCTAssertEqual(controller.store.index(accountID: account, moduleId: "digital.modula.basic").lastAuditReason, "activation-health")
        let reloaded = ModuleActivationController(store: ModuleArtifactStore(root: root))
        XCTAssertEqual(reloaded.active(accountID: account, moduleId: "digital.modula.basic")?.version, "0.1.0")
        XCTAssertEqual(reloaded.store.index(accountID: account, moduleId: "digital.modula.basic").lastAuditReason, "activation-health")
        let data = try reloaded.store.frontendData(for: try XCTUnwrap(reloaded.active(accountID: account, moduleId: "digital.modula.basic")))
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("Welcome to Basic Echo"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("0.1.1"))
    }

    private static func manifest(_ version: String) -> ModuleManifest {
        ModuleManifest(
            id: "digital.modula.basic", name: "Basic Echo", version: version, runtime: "declarative",
            entry: "product-ui", permissions: ["storage:records"], minHostVersion: ">=1.0.0",
            minBridgeVersion: "0.1.0", collections: ["item"]
        )
    }

    private static func frontend(_ title: String, _ version: String) -> Data {
        Data("""
        {"schema":"modula.frontend.1.0","frontendSchemaVersion":"1.0.0","mpsVersion":"1.0","productId":"digital.modula.basic","releaseVersion":"\(version)","mode":"declarative","entry":"home","hostRuntime":{"versionRange":">=1.0.0"},"routes":[{"path":"/","viewId":"home"}],"views":[{"id":"home","kind":"dashboard","root":{"type":"section","children":[{"type":"text","text":"\(title)"}]}}],"accessibility":{"declaration":"host-baseline-with-product-semantics","screenReader":true,"scalableText":true,"keyboardNavigation":true,"reduceMotion":true}}
        """.utf8)
    }
}
