import XCTest
@testable import Modula

@MainActor
final class ModuleHostEcosystemTests: XCTestCase {
    private var environment: ModuleEnvironment {
        ModuleEnvironment(colorScheme: "light", oled: false, reduceMotion: false, textScale: 1)
    }

    func testParsesDeclarativeFrontendAndRejectsExecutableFields() throws {
        let document = try ProductUIDocument.parse(data: Self.frontend(title: "Basic"), productId: "digital.modula.basic", version: "0.1.0")
        XCTAssertEqual(document.entry, "home")
        XCTAssertEqual(document.sha256.count, 64)
        XCTAssertThrowsError(try ProductUIDocument.parse(data: Self.frontend(title: "X", extra: ["script": "alert(1)"]), productId: "digital.modula.basic", version: "0.1.0")) { error in
            XCTAssertEqual(error as? ProductUIDocument.ParseError, .forbiddenField("script"))
        }
    }

    func testIdentityMismatchAndOversizedFrontendFailClosed() {
        XCTAssertThrowsError(try ProductUIDocument.parse(data: Self.frontend(title: "Basic"), productId: "other.module", version: "0.1.0"))
        let huge = Data(repeating: 0x61, count: ProductUIDocument.maxBytes + 1)
        XCTAssertThrowsError(try ProductUIDocument.parse(data: huge, productId: "digital.modula.basic", version: "0.1.0")) { error in
            XCTAssertEqual(error as? ProductUIDocument.ParseError, .oversized)
        }
    }

    func testCacheSlotsActivateAndRollbackWithoutTouchingPermissions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("modula-cache-\(UUID().uuidString)", isDirectory: true)
        let controller = ModuleActivationController(store: ModuleArtifactStore(root: root))
        let account = "acct-1"
        let v1 = try controller.installLocalPackage(
            accountID: account, moduleId: "digital.modula.basic", version: "0.1.0", releaseId: "r1",
            frontend: Self.frontend(title: "Basic 0.1.0"), hostManifest: Self.manifest("digital.modula.basic", "0.1.0")
        )
        XCTAssertEqual(v1.version, "0.1.0")
        XCTAssertEqual(controller.store.index(accountID: account, moduleId: "digital.modula.basic").activeReleaseId, "r1")

        let v2bytes = Self.frontend(title: "Basic 0.1.1", version: "0.1.1")
        _ = try controller.installLocalPackage(
            accountID: account, moduleId: "digital.modula.basic", version: "0.1.1", releaseId: "r2",
            frontend: v2bytes, hostManifest: Self.manifest("digital.modula.basic", "0.1.1")
        )
        XCTAssertEqual(controller.active(accountID: account, moduleId: "digital.modula.basic")?.version, "0.1.1")
        XCTAssertEqual(controller.store.release(in: .previousGood, accountID: account, moduleId: "digital.modula.basic")?.version, "0.1.0")

        let restored = try controller.rollback(accountID: account, moduleId: "digital.modula.basic", reason: "health")
        XCTAssertEqual(restored?.version, "0.1.0")
        XCTAssertEqual(controller.lastRollbackReason, "health")
    }

    func testBadStagedReleaseKeepsActive() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("modula-cache-\(UUID().uuidString)", isDirectory: true)
        let controller = ModuleActivationController(store: ModuleArtifactStore(root: root))
        _ = try controller.installLocalPackage(
            accountID: "acct-1", moduleId: "digital.modula.basic", version: "0.1.0", releaseId: "r1",
            frontend: Self.frontend(title: "Basic 0.1.0"), hostManifest: Self.manifest("digital.modula.basic", "0.1.0")
        )
        XCTAssertThrowsError(try controller.stageVerified(
            accountID: "acct-1", moduleId: "digital.modula.basic", version: "0.1.1", releaseId: "r-bad",
            frontend: Self.frontend(title: "Broken", version: "0.1.1"), frontendSha256: String(repeating: "ab", count: 32),
            mediaType: ProductUIDocument.mediaType, hostManifest: Self.manifest("digital.modula.basic", "0.1.1"),
            descriptor: nil
        ))
        XCTAssertEqual(controller.active(accountID: "acct-1", moduleId: "digital.modula.basic")?.version, "0.1.0")
    }

    func testActivationHealthFailureRestoresPreviousGood() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("modula-cache-\(UUID().uuidString)", isDirectory: true)
        let controller = ModuleActivationController(store: ModuleArtifactStore(root: root))
        _ = try controller.installLocalPackage(
            accountID: "acct-1", moduleId: "digital.modula.tasks", version: "0.1.0-beta.1", releaseId: "t1",
            frontend: Self.frontend(title: "Tasks", productId: "digital.modula.tasks", version: "0.1.0-beta.1"),
            hostManifest: Self.manifest("digital.modula.tasks", "0.1.0-beta.1")
        )
        _ = try controller.installLocalPackage(
            accountID: "acct-1", moduleId: "digital.modula.tasks", version: "0.1.1-beta.1", releaseId: "t2",
            frontend: Self.frontend(title: "Tasks 0.1.1", productId: "digital.modula.tasks", version: "0.1.1-beta.1"),
            hostManifest: Self.manifest("digital.modula.tasks", "0.1.1-beta.1"),
            activate: false
        )
        controller.failNextActivationHealth = true
        XCTAssertThrowsError(try controller.activate(accountID: "acct-1", moduleId: "digital.modula.tasks"))
        XCTAssertEqual(controller.active(accountID: "acct-1", moduleId: "digital.modula.tasks")?.version, "0.1.0-beta.1")
        XCTAssertEqual(controller.lastRollbackReason, "activation-health")
    }

    func testDeclarativePrepareDoesNotUseBundledReactRegistry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("modula-cache-\(UUID().uuidString)", isDirectory: true)
        let activation = ModuleActivationController(store: ModuleArtifactStore(root: root))
        _ = try activation.installLocalPackage(
            accountID: "acct-1", moduleId: "digital.modula.basic", version: "0.1.0", releaseId: "r1",
            frontend: Self.frontend(title: "Hello Basic"), hostManifest: Self.manifest("digital.modula.basic", "0.1.0")
        )
        let runtime = ModuleRuntimeController(manifests: [])
        runtime.setAccount("acct-1")
        runtime.activation = activation
        runtime.installationGate = { _ in .runnable(descriptor: nil) }
        let session = runtime.prepare(moduleID: "digital.modula.basic", environment: environment)
        XCTAssertEqual(session?.runtimeKind, .declarativeProductUI)
        XCTAssertEqual(session?.state, .ready)
        XCTAssertEqual(session?.productUI?.entry, "home")
        XCTAssertNil(session?.productUI?.raw["script"])
        XCTAssertNotEqual(session?.manifest.id, "digital.modula.vault-notes")
    }

    func testNoModuleIdSpecialCaseForVaultOrTasks() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Modula/ModuleRuntime/ProductUIRenderer.swift"))
        XCTAssertFalse(source.contains("digital.modula.vault-notes"))
        XCTAssertFalse(source.contains("digital.modula.tasks"))
        let host = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Modula/ModuleRuntime/ProductUIDocument.swift"))
        XCTAssertFalse(host.contains("digital.modula.vault-notes"))
    }

    func testHostAdvertisesBothLegacyAndProductUIContracts() {
        let vault2 = ModuleManifest(
            id: "digital.modula.vault-notes", name: "Vault Notes", version: "2.0.0-rc.2",
            runtime: "declarative", entry: "product-ui", permissions: [],
            minHostVersion: ">=1.0.0", minBridgeVersion: "0.1.0", collections: ["note"]
        )
        let bundled = ModuleManifest(
            id: "digital.modula.vault-notes", name: "Vault Notes", version: "1.7.0",
            runtime: "react-native", entry: "vault", permissions: [],
            minHostVersion: "0.1.0", minBridgeVersion: "0.1.0", collections: ["note"]
        )
        XCTAssertEqual(
            ModuleCompatibility.evaluate(vault2, hostVersions: ModuleCompatibility.advertisedHostVersions, bridgeVersion: "0.1.0"),
            .compatible
        )
        XCTAssertEqual(
            ModuleCompatibility.evaluate(bundled, hostVersions: ModuleCompatibility.advertisedHostVersions, bridgeVersion: "0.1.0"),
            .compatible
        )
    }

    func testPermissionReviewDoesNotCarryForwardNewCapabilities() {
        let store = ModulePermissionReviewStore()
        store.record(ModulePermissionReview(
            moduleId: "digital.modula.tasks", releaseId: "t1", descriptorRevision: "1",
            granted: ["storage:records"], denied: [], reviewedAt: Date()
        ))
        XCTAssertTrue(store.allows(moduleId: "digital.modula.tasks", releaseId: "t1", requested: ["storage:records"]))
        XCTAssertFalse(store.allows(moduleId: "digital.modula.tasks", releaseId: "t2", requested: ["storage:records", "mediaPicker"]))
        XCTAssertEqual(ModuleHostPermissions.purpose(for: "settings:register"),
                       "Register settings screens. This does not allow reading or writing settings values.")
    }

    func testLocalOnlyIntelligenceNeverInvented() {
        let session = ModuleSession(manifest: Self.manifest("digital.modula.intel", "0.1.0"), environment: environment)
        let result = ModuleCapabilityBroker.invoke("localIntelligence", session: session, localOnly: true)
        XCTAssertEqual(result, "CAPABILITY_UNAVAILABLE")
    }

    func testAccountIsolationOfArtifactCache() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("modula-cache-\(UUID().uuidString)", isDirectory: true)
        let controller = ModuleActivationController(store: ModuleArtifactStore(root: root))
        _ = try controller.installLocalPackage(
            accountID: "acct-a", moduleId: "digital.modula.basic", version: "0.1.0", releaseId: "r1",
            frontend: Self.frontend(title: "A"), hostManifest: Self.manifest("digital.modula.basic", "0.1.0")
        )
        XCTAssertNil(controller.active(accountID: "acct-b", moduleId: "digital.modula.basic"))
        XCTAssertNotNil(controller.active(accountID: "acct-a", moduleId: "digital.modula.basic"))
    }

    func testProductUIRuntimeSearchAndOfflineQueue() throws {
        let document = try ProductUIDocument.parse(data: Self.frontend(title: "Tasks", productId: "digital.modula.tasks"), productId: "digital.modula.tasks", version: "0.1.0")
        let session = ModuleSession(manifest: Self.manifest("digital.modula.tasks", "0.1.0"), environment: environment)
        let runtime = ProductUIRuntime(document: document, session: session, initialPath: "/")
        runtime.recordSource = { _, _ in
            [
                ProductUIRecord(id: "1", revision: 1, data: ["title": .string("Write report"), "status": .string("open")], deleted: false),
                ProductUIRecord(id: "2", revision: 1, data: ["title": .string("Buy milk"), "status": .string("done")], deleted: false),
            ]
        }
        runtime.refresh()
        runtime.query = "milk"
        XCTAssertEqual(runtime.bindingRecords("items").map(\.id), ["2"])
        runtime.online = false
        runtime.drafts["title"] = "Queued"
        runtime.perform(actionId: "createRecord")
        XCTAssertFalse(runtime.pendingMutations.isEmpty)
        XCTAssertTrue(runtime.pendingMutations[0].queuedOffline)
    }

    private static func manifest(_ id: String, _ version: String) -> ModuleManifest {
        ModuleManifest(
            id: id, name: id, version: version, runtime: "declarative", entry: "product-ui",
            permissions: ["backend.records.list", "backend.records.create"],
            minHostVersion: ">=1.0.0", minBridgeVersion: "0.1.0", collections: ["item"]
        )
    }

    private static func frontend(title: String, productId: String = "digital.modula.basic", version: String = "0.1.0", extra: [String: String] = [:]) -> Data {
        var extraJSON = ""
        for (key, value) in extra { extraJSON += ",\"\(key)\":\"\(value)\"" }
        let json = """
        {"schema":"modula.frontend.1.0","frontendSchemaVersion":"1.0.0","mpsVersion":"1.0","productId":"\(productId)","releaseVersion":"\(version)","mode":"declarative","entry":"home","hostRuntime":{"versionRange":">=1.0.0"},"routes":[{"path":"/","viewId":"home"}],"views":[{"id":"home","kind":"collection","title":"\(title)","bindings":[{"id":"items","source":"record.query","recordType":"item"}],"root":{"type":"section","children":[{"type":"text","text":"\(title)"},{"type":"search","text":"Search"},{"type":"recordList","binding":"items","action":"openRecord","children":[{"type":"recordRow","binding":"items","children":[{"type":"text","binding":"items","valuePath":"title"}]}]},{"type":"button","text":"New","action":"createRecord"}]},"states":{"loading":{"type":"loadingState","text":"Loading"},"empty":{"type":"emptyState","text":"Empty"},"error":{"type":"errorState","text":"Error"}}}],"actions":[{"id":"openRecord","family":"route.open","label":"Open","route":"/"},{"id":"createRecord","family":"record.create","label":"Create","recordType":"item"}],"accessibility":{"declaration":"host-baseline-with-product-semantics","screenReader":true,"scalableText":true,"keyboardNavigation":true,"reduceMotion":true}\(extraJSON)}
        """
        return Data(json.utf8)
    }
}
